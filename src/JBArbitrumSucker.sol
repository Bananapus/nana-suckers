// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IBridge} from "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";
import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {AddressAliasHelper} from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import {ArbL1GatewayRouter} from "./interfaces/ArbL1GatewayRouter.sol";
import {ArbL2GatewayRouter} from "./interfaces/ArbL2GatewayRouter.sol";
import {IArbGatewayRouter} from "./interfaces/IArbGatewayRouter.sol";
import {JBRemoteToken} from "./structs/JBRemoteToken.sol";
import {JBInboxTreeRoot} from "./structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "./structs/JBMessageRoot.sol";
import {JBLayer} from "./enums/JBLayer.sol";
import {JBSucker, IJBSuckerDeployer, JBAddToBalanceMode} from "./JBSucker.sol";
import {JBArbitrumSuckerDeployer} from "./deployers/JBArbitrumSuckerDeployer.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

import {ARBAddresses} from "./libraries/ARBAddresses.sol";
import {ARBChains} from "./libraries/ARBChains.sol";

/// @notice A `JBSucker` implementation to suck tokens between two chains connected by an Arbitrum bridge.
// NOTICE: UNFINISHED!
contract JBArbitrumSucker is JBSucker {
    error L1GatewayUnsupported();
    error ChainNotSupported();
    error NotEnoughGas();

    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The layer that this contract is on.
    JBLayer public immutable LAYER;

    /// @notice The gateway router for the specific chain
    IArbGatewayRouter public immutable GATEWAYROUTER;

    /// @notice The inbox used to send messages between the local and remote sucker.
    IInbox public immutable ARBINBOX;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//
    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        JBAddToBalanceMode atbMode
    ) JBSucker(directory, tokens, permissions, peer, atbMode, IJBSuckerDeployer(msg.sender).TEMP_ID_STORE()) {
        // Layer specific properties
        uint256 _chainId = block.chainid;

        // Set LAYER based on the chain ID.
        if (_chainId == ARBChains.ETH_CHAINID || _chainId == ARBChains.ETH_SEP_CHAINID) {
            // Set the layer
            LAYER = JBLayer.L1;

            // Set the inbox depending on the chain
            _chainId == ARBChains.ETH_CHAINID
                ? ARBINBOX = IInbox(ARBAddresses.L1_ETH_INBOX)
                : ARBINBOX = IInbox(ARBAddresses.L1_SEP_INBOX);
        } else if (_chainId == ARBChains.ARB_CHAINID || _chainId == ARBChains.ARB_SEP_CHAINID) {
            LAYER = JBLayer.L2;
        } else {
            revert ChainNotSupported();
        }

        GATEWAYROUTER = JBArbitrumSuckerDeployer(msg.sender).gatewayRouter();
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainID() external view virtual override returns (uint256 chainId) {
        uint256 _chainId = block.chainid;
        if (_chainId == ARBChains.ETH_CHAINID) return ARBChains.ARB_CHAINID;
        if (_chainId == ARBChains.ARB_CHAINID) return ARBChains.ETH_CHAINID;
        if (_chainId == ARBChains.ETH_SEP_CHAINID) return ARBChains.ARB_SEP_CHAINID;
        if (_chainId == ARBChains.ARB_SEP_CHAINID) return ARBChains.ETH_SEP_CHAINID;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Uses the L1/L2 gateway to send the root and assets over the bridge to the peer.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, JBRemoteToken memory remoteToken) internal override {
        // TODO: Handle the `transportPayment`
        // if (transportPayment == 0) {
        //     revert UNEXPECTED_MSG_VALUE();
        // }

        // Get the amount to send and then clear it.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        if (remoteToken.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // Build the calldata that will be send to the peer. This will call `JBSucker.fromRemote` on the remote peer.
        bytes memory data = abi.encodeCall(
            JBSucker.fromRemote,
            (
                JBMessageRoot({
                    token: remoteToken.addr,
                    amount: amount,
                    remoteRoot: JBInboxTreeRoot({nonce: nonce, root: outbox[token].tree.root()})
                })
            )
        );

        // Depending on which layer we are on, send the call to the other layer.
        if (LAYER == JBLayer.L1) {
            _toL2(token, transportPayment, amount, data, remoteToken);
        } else {
            _toL1(token, amount, data, remoteToken);
        }

        // Emit an event for the relayers to watch for.
        emit RootToRemote(outbox[token].tree.root(), token, outbox[token].tree.count - 1, nonce);
    }

    /// @notice Bridge the `token` and data to the remote L1 chain.
    /// @param token The token to bridge.
    /// @param amount The amount of tokens to bridge.
    /// @param data The calldata to send to the remote chain. This calls `JBSucker.fromRemote` on the remote peer.
    /// @param remoteToken Information about the remote token to bridged to.
    function _toL1(address token, uint256 amount, bytes memory data, JBRemoteToken memory remoteToken) internal {
        uint256 nativeValue;

        // Revert if there's a `msg.value`. Sending a message to L1 does not require any payment.
        if (msg.value != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        // If the token is an ERC-20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            SafeERC20.forceApprove(IERC20(token), GATEWAYROUTER.getGateway(token), amount);

            ArbL2GatewayRouter(address(GATEWAYROUTER)).outboundTransfer(
                remoteToken.addr, address(PEER), amount, bytes("")
            );
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        // Send the message to the peer with the redeemed ETH.
        // Address `100` is the ArbSys precompile address.
        ArbSys(address(100)).sendTxToL1{value: nativeValue}(address(PEER), data);
    }

    /// @notice Bridge the `token` and data to the remote L2 chain.
    /// @param token The token to bridge.
    /// @param amount The amount of tokens to bridge.
    /// @param data The calldata to send to the remote chain. This calls `JBSucker.fromRemote` on the remote peer.
    function _toL2(
        address token,
        uint256 transportPayment,
        uint256 amount,
        bytes memory data,
        JBRemoteToken memory /* remoteToken */
    ) internal {
        uint256 nativeValue;
        uint256 _maxSubmissionCost = ARBINBOX.calculateRetryableSubmissionFee(data.length, 0.2 gwei);
        uint256 _feeTotal = _maxSubmissionCost + (MESSENGER_BASE_GAS_LIMIT * 0.2 gwei);

        // Ensure we bridge enough for gas costs on L2 side
        if (transportPayment < _feeTotal) revert NotEnoughGas();

        // If the token is an ERC-20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens to be bridged.
            SafeERC20.forceApprove(IERC20(token), GATEWAYROUTER.getGateway(token), amount);

            // Perform the ERC-20 bridge transfer.
            ArbL1GatewayRouter(address(GATEWAYROUTER)).outboundTransferCustomRefund{value: transportPayment}({
                _token: token,
                _refundTo: msg.sender,
                _to: address(PEER),
                _amount: amount,
                _maxGas: MESSENGER_BASE_GAS_LIMIT, // minimum appears to be 275000 per their sdk - MESSENGER_BASE_GAS_LIMIT = 300k here
                _gasPriceBid: 0.2 gwei, // sane enough for now - covers moderate congestion, maybe decide client side in the future
                _data: bytes(abi.encode(_maxSubmissionCost, data)) // @note: maybe this is zero if we pay with msg.value? we'll see in testing
            });
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        // Ensure we bridge enough for gas costs on L2 side
        // transportPayment is ref of msg.value
        if (nativeValue + _feeTotal > transportPayment) revert NotEnoughGas();

        // Create the retryable ticket containing the merkleRoot.
        // TODO: We could even make this unsafe.
        ARBINBOX.createRetryableTicket{value: transportPayment}({
            to: address(PEER),
            l2CallValue: nativeValue,
            maxSubmissionCost: _maxSubmissionCost,
            excessFeeRefundAddress: msg.sender,
            callValueRefundAddress: msg.sender,
            gasLimit: MESSENGER_BASE_GAS_LIMIT,
            maxFeePerGas: 0.2 gwei,
            data: data
        });
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal view override returns (bool _valid) {
        // If we are the L1 peer,
        if (LAYER == JBLayer.L1) {
            IBridge bridge = ARBINBOX.bridge();
            // Check that the sender is the bridge and that the outbox has our peer as the sender.
            return sender == address(bridge) && address(PEER) == IOutbox(bridge.activeOutbox()).l2ToL1Sender();
        }

        // If we are the L2 peer, check using the `AddressAliasHelper`.
        return sender == AddressAliasHelper.applyL1ToL2Alias(address(PEER));
    }
}
