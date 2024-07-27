// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBTokenMapping} from "./structs/JBTokenMapping.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";

import {IJBCCIPSuckerDeployer} from "src/interfaces/IJBCCIPSuckerDeployer.sol";
import {JBSucker, JBAddToBalanceMode} from "./JBSucker.sol";
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

/// @notice A `JBSucker` implementation which uses Chainlink's [CCIP](https://docs.chain.link/ccip) to bridge tokens and send messages (merkle roots) between chains.
contract JBCCIPSucker is JBSucker, ModifiedReceiver {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    /// @notice The CCIP router contract to use for sending messages and tokens across chains.
    IRouterClient public ROUTER;

    /// @notice The chain ID that the remote peer is located on.
    uint256 public immutable REMOTE_CHAIN_ID;

    /// @notice The CCIP selector (a CCIP-specific ID) for the remote chain.
    /// @dev To find a chain's CCIP selector, see [CCIP Supported Networks](https://docs.chain.link/ccip/supported-networks).
    uint64 public immutable REMOTE_CHAIN_SELECTOR;

    // TODO: Change this to `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` for production.
    address public immutable WETH;

    error MUST_PAY_ROUTER_FEE();
    error LOCAL_NATIVE_ON_MAINNET_ONLY();
    error REMOTE_OF_NATIVE_MUST_BE_WETH();
    error TOKEN_NOT_SUPPORTED();
    error InsufficientMaxRouterFee(uint256 balance, uint256 fees);
    error FailedToRefund();

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        JBAddToBalanceMode atbMode
    ) JBSucker(directory, tokens, permissions, peer, atbMode, IJBCCIPSuckerDeployer(msg.sender).TEMP_PROJECT_ID()) {
        REMOTE_CHAIN_ID = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_ID();
        REMOTE_CHAIN_SELECTOR = IJBCCIPSuckerDeployer(msg.sender).REMOTE_CHAIN_SELECTOR();
        ROUTER = IRouterClient(i_ccipRouter);
        // TODO: Change this to `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` for production.
        WETH = CCIPHelper.wethOfChain(block.chainid);
    }

    /// @notice Map an ERC-20 token on the local chain to an ERC-20 token on the remote chain, allowing that token to be bridged.
    /// @param map The local and remote terminal token addresses to map, and minimum amount/gas limits for bridging them.
    function mapToken(JBTokenMapping calldata map) public override {
        address token = map.localToken;

        // TODO: Can this be deleted? Why is it commented out?
        /* bool isNative = map.localToken == JBConstants.NATIVE_TOKEN;
        // If the token being mapped is the native token, the `remoteToken` must also be the native token.
        // The native token can also be mapped to the 0 address, which is used to disable native token bridging.
        if (isNative && map.remoteToken != JBConstants.NATIVE_TOKEN && map.remoteToken != address(0)) {
            revert INVALID_NATIVE_REMOTE_ADDRESS(map.remoteToken);
        } */

        // Enforce a reasonable minimum gas limit for bridging. A minimum which is too low could lead to the loss of funds.
        if (map.minGas < MESSENGER_ERC20_MIN_GAS_LIMIT) {
            revert BELOW_MIN_GAS(MESSENGER_ERC20_MIN_GAS_LIMIT, map.minGas);
        }

        // The caller must be the project owner or have their permission to `MAP_SUCKER_TOKEN`s.
        _requirePermissionFrom(DIRECTORY.PROJECTS().ownerOf(PROJECT_ID), PROJECT_ID, JBPermissionIds.MAP_SUCKER_TOKEN);

        // If bridging is being disabled, send any remaining outbox funds to the remote chain.
        // Note: setting the remote token to the 0 address disables bridging.
        if (map.remoteToken == address(0) && outbox[token].balance != 0) _sendRoot(0, token, remoteTokenFor[token]);

        // Update the token mapping.
        remoteTokenFor[token] =
            JBRemoteToken({minGas: map.minGas, addr: map.remoteToken, minBridgeAmount: map.minBridgeAmount});
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Send the outbox root for the specified token to the remote peer.
    /// @dev For more information about router fees, see [CCIP Billing](https://docs.chain.link/ccip/billing).
    /// @param maxRouterFee The maximum amount (out of `msg.value`) to pay the router's message fee. Any remaining value will be refunded to the caller.
    /// @param token The token whose outbox tree is being bridged.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 maxRouterFee, address token, JBRemoteToken memory remoteToken) internal override {
        bool localIsNative = token == JBConstants.NATIVE_TOKEN;
        // TODO: Only check for `chainId == 1` in production.
        bool willSendWeth = localIsNative && (block.chainid == 1 || block.chainid == 11155111);
        // TODO: Should we inline this?
        address remoteTokenAddress = remoteToken.addr;

        // Revert if the caller did not include a max router fee.
        // TODO: Should we add ` || msg.value < maxRouterFee`?
        if (maxRouterFee == 0) {
            revert MUST_PAY_ROUTER_FEE();
        }

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteTokenAddress == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // TODO: Should we add something like this back for production?
        // Only support local native tokens (and wrapping) on Ethereum mainnet.
        // if (block.chainid != 1 && localIsNative) revert LOCAL_NATIVE_ON_MAINNET_ONLY();

        // Revert if the remote token is the native token – we can only bridge wrapped native tokens.
        if (remoteTokenAddress == JBConstants.NATIVE_TOKEN) revert REMOTE_OF_NATIVE_MUST_BE_WETH();

        // Make sure the router supports the tokens being bridged.
        address[] memory supportedForTransferList = ROUTER.getSupportedTokens(REMOTE_CHAIN_SELECTOR);
        if (!_isTokenInList(supportedForTransferList, willSendWeth ? WETH : token)) {
            revert TOKEN_NOT_SUPPORTED();
        }

        // Get the amount being bridged, then clear it from the outbox tree.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        // Get the outbox tree's root.
        bytes32 root = outbox[token].tree.root();

        // Add the token and amount to an array for the CCIP message.
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: willSendWeth ? WETH : token, amount: amount});

        // Create our CCIP message with the root and tokens being bridged.
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(
                JBMessageRoot({
                    token: remoteToken.addr,
                    amount: amount,
                    remoteRoot: JBInboxTreeRoot({nonce: nonce, root: root})
                })
            ),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                // Set the gas limit as an extra argument.
                Client.EVMExtraArgsV1({gasLimit: MESSENGER_BASE_GAS_LIMIT + remoteToken.minGas})
            ),
            // Pay the router fee using native tokens (from the `msg.value`).
            feeToken: address(0)
        });

        // Calculate the router fee for our message.
        uint256 fees = ROUTER.getFee({destinationChainSelector: REMOTE_CHAIN_SELECTOR, message: evm2AnyMessage});

        // If the caller didn't send enough to cover the router fee, revert.
        if (fees > maxRouterFee) {
            revert InsufficientMaxRouterFee(maxRouterFee, fees);
        }

        // If the local token is the native token, wrap it.
        if (willSendWeth) IWETH9(WETH).deposit{value: amount}();

        // Give the router approval to spend `amount` tokens on this contract's behalf.
        // `amount` is the amount being bridged.
        SafeERC20.forceApprove(IERC20(willSendWeth ? WETH : token), address(ROUTER), amount);

        // TODO: When we add message retried, we'll need to handle this `messageId`.
        // Send the message.
        /* messageId =  */
        ROUTER.ccipSend{value: fees}({destinationChainSelector: REMOTE_CHAIN_SELECTOR, message: evm2AnyMessage});

        // Use a zero-indexed tree count in the event.
        uint256 index = outbox[token].tree.count - 1;

        // Emit an event for relayers to watch for.
        emit RootToRemote(root, token, index, nonce);

        // Return the remaining `msg.value` to the caller now that fees have been paid.
        (bool sent,) = msg.sender.call{value: msg.value - fees}("");
        if (!sent) revert FailedToRefund();
    }

    /// @notice Checks whether the `targetToken` is in the `tokenList`.
    /// @param tokenList An `address[]` of tokens supported by the router.
    /// @param targetToken The token to check for in the list.
    function _isTokenInList(address[] memory tokenList, address targetToken) internal pure returns (bool) {
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == targetToken) {
                return true;
            }
        }

        return false;
    }

    /// @notice Receive a CCIP message from the remote peer.
    /// @param message An `Any2EVMMessage` from the router.
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override onlyRouter {
        JBMessageRoot memory root = abi.decode(message.data, (JBMessageRoot));

        // If the message wasn't sent by this sucker's peer (which has the same address as this contract), revert.
        address origin = abi.decode(message.sender, (address));

        if (origin != address(this)) revert NOT_PEER();

        // Increase how much can be added to the project's balance by the amount received.
        // TODO: Should this check for atb mode? I don't remember exactly how this worked.
        amountToAddToBalance[root.token] += root.amount;

        // If the received tree has a greater nonce than the current inbox tree, update the inbox tree.
        // Note: We can't revert because this could be a native token transfer. If we reverted, we would lose the native tokens.
        // TODO: Could we revert here since `_sendRoot(…)` reverts when the remote token is `JBConstants.NATIVE_TOKEN`? Not essential...
        if (root.remoteRoot.nonce > inbox[root.token].nonce) {
            inbox[root.token] = root.remoteRoot;
            emit NewInboxTreeRoot(root.token, root.remoteRoot.nonce, root.remoteRoot.root);
        }
    }

    /// @notice Always reverts.
    /// @dev The CCIP sucker does not use `fromRemote(…)` because the router calls `_ccipReceive(…)` directly.
    function fromRemote(JBMessageRoot calldata) external payable override {
        revert();
    }

    /// @notice Checks whether `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
        if (sender != address(i_ccipRouter)) return false;

        // Decode the CCIP message from the router's calldata and extract the origin address.
        Client.Any2EVMMessage memory message = abi.decode(msg.data, (Client.Any2EVMMessage));
        address origin = abi.decode(message.sender, (address));

        return origin == PEER;
    }

    /// @notice Returns the peer sucker's chain ID.
    /// @return chainId The remote chain ID.
    function peerChainID() external view override returns (uint256 chainId) {
        return REMOTE_CHAIN_ID;
    }
}
