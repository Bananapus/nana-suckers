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

import {BPSucker} from "./BPSucker.sol";
import {BPSuckerHook} from "./BPSuckerHook.sol";
import {BPMessageRoot} from "./structs/BPMessageRoot.sol";
import {BPRemoteToken} from "./structs/BPRemoteToken.sol";
import {BPInboxTreeRoot} from "./structs/BPInboxTreeRoot.sol";
import {OPMessenger} from "./interfaces/OPMessenger.sol";
import {OPStandardBridge} from "./interfaces/OPStandardBridge.sol";
import {MerkleLib} from "./utils/MerkleLib.sol";

/// @notice A `BPSucker` implementation to suck tokens between two chains connected by an OP Bridge.
contract BPOptimismSucker is BPSucker, BPSuckerHook {
    using MerkleLib for MerkleLib.Tree;
    using BitMaps for BitMaps.BitMap;

    event SuckingToRemote(address token, uint64 nonce);

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The messenger used to send messages between the local and remote sucker.
    OPMessenger public immutable OPMESSENGER;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    OPStandardBridge public immutable OPBRIDGE;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBPrices prices,
        IJBRulesets rulesets,
        OPMessenger messenger,
        OPStandardBridge bridge,
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address peer,
        uint256 projectId
    ) BPSucker(directory, tokens, permissions, peer, projectId) BPSuckerHook(prices, rulesets) {
        OPMESSENGER = messenger;
        OPBRIDGE = bridge;
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Use the `OPMESSENGER` to send the outbox tree for the `token` and the corresponding funds to the peer over the `OPBRIDGE`.
    /// @param transportPayment the amount of `msg.value` that is going to get paid for sending this message.
    /// @param token The token to bridge the outbox tree for.
    /// @param remoteToken Information about the remote token being bridged to.
    function _sendRoot(uint256 transportPayment, address token, BPRemoteToken memory remoteToken) internal override {
        uint256 nativeValue;

        // Revert if there's a `msg.value`. The OP bridge does not expect to be paid.
        if (transportPayment != 0) {
            revert UNEXPECTED_MSG_VALUE();
        }

        // Get the amount to send and then clear it from the outbox tree.
        uint256 amount = outbox[token].balance;
        delete outbox[token].balance;

        // Increment the outbox tree's nonce.
        uint64 nonce = ++outbox[token].nonce;

        // Ensure the token is mapped to an address on the remote chain.
        if (remoteToken.addr == address(0)) {
            revert TOKEN_NOT_MAPPED(token);
        }

        // If the token is an ERC20, bridge it to the peer.
        if (token != JBConstants.NATIVE_TOKEN) {
            // Approve the tokens bing bridged.
            SafeERC20.forceApprove(IERC20(token), address(OPBRIDGE), amount);

            // Bridge the tokens to the peer sucker.
            OPBRIDGE.bridgeERC20To({
                localToken: token,
                remoteToken: remoteToken.addr,
                to: PEER,
                amount: amount,
                minGasLimit: remoteToken.minGas,
                extraData: bytes("")
            });
        } else {
            // Otherwise, the token is the native token, and the amount will be sent as `msg.value`.
            nativeValue = amount;
        }

        bytes32 _root = outbox[token].tree.root();
        uint256 _index = outbox[token].tree.count - 1;

        // Send the message to the peer with the redeemed ETH.
        // slither-disable-next-line arbitrary-send-eth
        OPMESSENGER.sendMessage{value: nativeValue}(
            PEER,
            abi.encodeCall(
                BPSucker.fromRemote,
                (
                    BPMessageRoot({
                        token: remoteToken.addr,
                        amount: amount,
                        remoteRoot: BPInboxTreeRoot({nonce: nonce, root: _root})
                    })
                )
            ),
            MESSENGER_BASE_GAS_LIMIT
        );

        // Emit an event for the relayers to watch for.
        emit RootToRemote(_root, token, _index, nonce);
    }

    /// @notice Checks if the `sender` (`msg.sender`) is a valid representative of the remote peer.
    /// @param sender The message's sender.
    function _isRemotePeer(address sender) internal override returns (bool valid) {
        return sender == address(OPMESSENGER) && OPMESSENGER.xDomainMessageSender() == PEER;
    }
}
