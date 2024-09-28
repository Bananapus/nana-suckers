// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";

import "./JBSucker.sol";
import {IJBCCIPSuckerDeployer} from "src/interfaces/IJBCCIPSuckerDeployer.sol";
import {ICCIPRouter, IWrappedNativeToken} from "src/interfaces/ICCIPRouter.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBCCIPSuckerDeployer} from "./deployers/JBCCIPSuckerDeployer.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPHelper} from "src/libraries/CCIPHelper.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

/// @notice A `JBSucker` implementation to suck tokens between chains with Chainlink CCIP
contract JBCCIPSucker is JBSucker, IAny2EVMMessageReceiver {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    ICCIPRouter internal immutable CCIP_ROUTER;
    uint256 public remoteChainId;
    uint64 public remoteChainSelector;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBCCIPSucker_FailedToRefundFee();
    error JBCCIPSucker_InvalidRouter(address router);
    error JBCCIPSucker_UnexpectedAmountOfTokens(uint256 nOfTokens);

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        JBAddToBalanceMode atbMode
    )
        JBSucker(directory, permissions, tokens, peer, atbMode, IJBCCIPSuckerDeployer(msg.sender).TEMP_ID_STORE())
    {
        remoteChainId = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_ID();
        remoteChainSelector = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_SELECTOR();
        CCIP_ROUTER = ICCIPRouter(CCIPHelper.routerOfChain(block.chainid));
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal override {
        // Make sure we are attempting to pay the bridge
        if (transportPayment == 0) revert JBSucker_ExpectedMsgValue();

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteToken.addr == address(0)) revert JBSucker_TokenNotMapped(token);

        // Get the outbox in storage.
        JBOutboxTree storage outbox = _outboxOf[token];

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox.balance;
        delete outbox.balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox.nonce;

        bytes32 root = outbox.tree.root();
        uint256 index = outbox.tree.count - 1;

        // Emit an event for the relayers to watch for.
        // We do this before changing the `token` in the case where it is the native asset.
        emit RootToRemote({root: root, token: token, index: index, nonce: nonce, caller: msg.sender});

        // Wrap the token if it's native
        if (token == JBConstants.NATIVE_TOKEN) {
            // Get the wrapped native token.
            IWrappedNativeToken wrapped_native = CCIP_ROUTER.getWrappedNative();
            // Deposit the wrapped native asset.
            wrapped_native.deposit{value: amount}();
            // Update the token to be the wrapped native asset.
            token = address(wrapped_native);
        }

        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(PEER),
            data: abi.encode(
                JBMessageRoot({
                    token: remoteToken.addr,
                    amount: amount,
                    remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root})
                })
            ),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: MESSENGER_BASE_GAS_LIMIT + remoteToken.minGas})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees,
            // We pay in the native asset.
            feeToken: address(0)
        });

        // Get the fee required to send the CCIP message
        uint256 fees = CCIP_ROUTER.getFee({destinationChainSelector: remoteChainSelector, message: message});

        if (fees > transportPayment) {
            revert JBSucker_InsufficientMsgValue(transportPayment, fees);
        }

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        SafeERC20.forceApprove(IERC20(token), address(CCIP_ROUTER), amount);

        // TODO: Handle this messageId- for later version with message retries
        // Send the message through the router and store the returned message ID
        /* messageId =  */
        CCIP_ROUTER.ccipSend{value: fees}({destinationChainSelector: remoteChainSelector, message: message});

        // Refund remaining balance.
        (bool sent,) = msg.sender.call{value: msg.value - fees}("");
        if (!sent) revert JBCCIPSucker_FailedToRefundFee();
    }

    /// @notice The entrypoint for the CCIP router to call. This function should
    /// never revert, all errors should be handled internally in this contract.
    /// @param any2EvmMessage The message to process.
    /// @dev Extremely important to ensure only router calls this.
    function ccipReceive(Client.Any2EVMMessage calldata any2EvmMessage) external override {
        // only calls from the set router are accepted.
        if (msg.sender != address(CCIP_ROUTER)) revert JBSucker_NotPeer(msg.sender);

        // Decode the message root from the peer
        JBMessageRoot memory root = abi.decode(any2EvmMessage.data, (JBMessageRoot));
        address origin = abi.decode(any2EvmMessage.sender, (address));

        // Make sure that the message came from our peer.
        if (origin != PEER || any2EvmMessage.sourceChainSelector != remoteChainSelector) {
            revert JBSucker_NotPeer(origin);
        }

        if (any2EvmMessage.destTokenAmounts.length != 1) {
            // This should never happen, we *always* send a tokenAmount.
            revert JBCCIPSucker_UnexpectedAmountOfTokens(any2EvmMessage.destTokenAmounts.length);
        }

        // As far as the sucker contract is aware wrapped natives are not a thing, it only handles ERC20s or native.
        Client.EVMTokenAmount memory tokenAmount = any2EvmMessage.destTokenAmounts[0];
        if (root.token == JBConstants.NATIVE_TOKEN) {
            // We can (safely) assume that the token that is set in the `destTokenAmounts` is a valid wrapped native.
            // If this ends up not being the case then our sanity check to see if we unwrapped the native asset will
            // fail.
            IWrappedNativeToken wrapped_native = IWrappedNativeToken(tokenAmount.token);
            uint256 balanceBefore = _balanceOf({token: JBConstants.NATIVE_TOKEN, addr: address(this)});

            // Withdraw the wrapped native asset.
            wrapped_native.withdraw(tokenAmount.amount);

            // Sanity check the unwrapping of the native asset.
            assert(
                balanceBefore + tokenAmount.amount == _balanceOf({token: JBConstants.NATIVE_TOKEN, addr: address(this)})
            );
        }

        // Call ourselves to process the root.
        this.fromRemote(root);
    }

    /// @notice Unused in this context.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
        // NOTICE: We do not check if its the `PEER` here, as this contract is supposed to be the caller *NOT* the PEER.
        return sender == address(this);
    }

    /// @notice Allow sucker implementations to add/override mapping rules to suite their specific needs.
    function _validateTokenMapping(JBTokenMapping calldata map) internal pure virtual override {
        // This sucker has an override since it could connect to a non-ETH chain, so we allow the `NATIVE_TOKEN` to map
        // to a token that is not the wrapped token on the remote.

        // Enforce a reasonable minimum gas limit for bridging. A minimum which is too low could lead to the loss of
        // funds.
        if (map.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT && map.localToken != JBConstants.NATIVE_TOKEN) {
            revert JBSucker_BelowMinGas(map.minGas, MESSENGER_ERC20_MIN_GAS_LIMIT);
        }
    }

    /// @notice Return the current router
    /// @return CCIP router address
    function getRouter() public view returns (address) {
        return address(CCIP_ROUTER);
    }

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainId() external view virtual override returns (uint256 chainId) {
        // Return the remote chain id
        return remoteChainId;
    }

    /// @notice IERC165 supports an interfaceId
    /// @param interfaceId The interfaceId to check
    /// @return true if the interfaceId is supported
    /// @dev Should indicate whether the contract implements IAny2EVMMessageReceiver
    /// e.g. return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId
    /// This allows CCIP to check if ccipReceive is available before calling it.
    /// If this returns false or reverts, only tokens are transferred to the receiver.
    /// If this returns true, tokens are transferred and ccipReceive is called atomically.
    /// Additionally, if the receiver address does not have code associated with
    /// it at the time of execution (EXTCODESIZE returns 0), only tokens will be transferred.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
