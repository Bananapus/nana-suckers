// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A struct that represents a token on the remote chain.
/// @custom:member minGas The minimum gas to use when bridging.
/// @custom:member addr The address of the token on the remote chain.
/// @custom:member minBridgeAmount The minimum amount to bridge.
struct JBRemoteToken {
    bool enabled;
    uint32 minGas;
    address addr;
    uint256 minBridgeAmount;
}
