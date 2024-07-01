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

import {IJBCCIPSuckerDeployer} from "src/interfaces/IJBCCIPSuckerDeployer.sol";
import {JBSucker, IJBSuckerDeployer, JBAddToBalanceMode} from "./JBSucker.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBCCIPSuckerDeployer} from "./deployers/JBCCIPSuckerDeployer.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

import {ModifiedReceiver} from "./utils/ModifiedReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {CCIPHelper} from "src/libraries/CCIPHelper.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

/// @notice A `JBSucker` implementation to suck tokens between chains with Chainlink CCIP
contract JBCCIPSucker is JBSucker, ModifiedReceiver {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    uint256 public immutable remoteChainId;
    uint64 public immutable remoteChainSelector;

    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    event SuckingToRemote(address token, uint64 nonce);

    error MUST_PAY_BRIDGE();
    error NATIVE_ON_ETH_ONLY();
    error REMOTE_OF_NATIVE_MUST_BE_WETH();
    error NotEnoughBalance(uint256 balance, uint256 fees);
    error FailedToRefundFee();

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        JBAddToBalanceMode atbMode
    ) JBSucker(directory, tokens, permissions, peer, atbMode, IJBCCIPSuckerDeployer(msg.sender).TEMP_ID_STORE()) {
        remoteChainId = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_ID();
        remoteChainSelector = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_SELECTOR();
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal override {
        bool localIsNative = token == JBConstants.NATIVE_TOKEN;
        bool willSendWeth = localIsNative && block.chainid == 1;
        address remoteTokenAddress = remoteToken.addr;

        // Make sure we are attempting to pay the bridge
        if (transportPayment == 0) {
            revert MUST_PAY_BRIDGE();
        }

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteTokenAddress == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Only support native backing token (and wrapping) if on Ethereum
        if (block.chainid != 1 && localIsNative) revert NATIVE_ON_ETH_ONLY();

        // Cannot bridge native tokens unless wrapped
        if (remoteTokenAddress == JBConstants.NATIVE_TOKEN) revert REMOTE_OF_NATIVE_MUST_BE_WETH();

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        bytes32 _root = outbox[token].tree.root();
        uint256 _index = outbox[token].tree.count - 1;

        // Wrap the token if it's native
        if (willSendWeth) IWETH9(CCIPHelper.wethOfChain(block.chainid)).deposit{value: amount}();

        // Set the token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: willSendWeth ? WETH : token, amount: amount});

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(
                JBMessageRoot({
                    token: remoteToken.addr,
                    amount: amount,
                    remoteRoot: JBInboxTreeRoot({nonce: nonce, root: _root})
                })
            ),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit
                Client.EVMExtraArgsV1({gasLimit: MESSENGER_BASE_GAS_LIMIT + remoteToken.minGas})
            ),
            // Pay the fee using the native asset.
            feeToken: address(0)
        });

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee({destinationChainSelector: remoteChainSelector, message: evm2AnyMessage});

        if (fees > transportPayment) {
            revert NotEnoughBalance(transportPayment, fees);
        }

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        SafeERC20.forceApprove(IERC20(token), address(router), amount);

        // TODO: Handle this messageId- for later version with message retries
        // Send the message through the router and store the returned message ID
        /* messageId =  */
        router.ccipSend{value: fees}({destinationChainSelector: remoteChainSelector, message: evm2AnyMessage});

        // Emit an event for the relayers to watch for.
        emit RootToRemote(_root, token, _index, nonce);

        // Refund remaining balance.
        (bool sent,) = msg.sender.call{value: msg.value - fees}("");
        if (!sent) revert FailedToRefundFee();
    }

    /// @notice Override this function in your implementation.
    /// @param message Any2EVMMessage
    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual override {
        // Decode the message root from the peer
        JBMessageRoot memory root = abi.decode(message.data, (JBMessageRoot));
        address origin = abi.decode(message.sender, (address));

        // Make sure that the message came from our peer.
        if (origin != address(this)) revert NOT_PEER();

        // Increase the outstanding amount to be added to the project's balance by the amount being received.
        amountToAddToBalance[root.token] += root.amount;

        // If the received tree's nonce is greater than the current inbox tree's nonce, update the inbox tree.
        // We can't revert because this could be a native token transfer. If we reverted, we would lose the native tokens.
        if (root.remoteRoot.nonce > inbox[root.token].nonce) {
            inbox[root.token] = root.remoteRoot;
            emit NewInboxTreeRoot(root.token, root.remoteRoot.nonce, root.remoteRoot.root);
        }
    }

    /// @notice This function is not in use for the CCIP sucker.
    function fromRemote(JBMessageRoot calldata) external payable virtual override {
        revert();
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
        if (sender != address(i_ccipRouter)) return false;

        Client.Any2EVMMessage memory message = abi.decode(msg.data, (Client.Any2EVMMessage));
        address origin = abi.decode(message.sender, (address));

        return origin == PEER;
    }

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256 chainId) {
        // Return the remote chain id
        return remoteChainId;
    }
}
