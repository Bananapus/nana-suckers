// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBTokenMapping} from "../structs/JBTokenMapping.sol";
import {JBClaim} from "src/structs/JBClaim.sol";
import {JBInboxTreeRoot} from "src/structs/JBInboxTreeRoot.sol";

interface IJBSucker {
    function claim(JBClaim calldata claimData) external;

    function claim(JBClaim[] calldata claims) external;

    function PEER() external view returns (address);

    function peerChainID() external view returns (uint256 chainId);

    function inbox(address token) external view returns (uint64 nonce, bytes32 root);

    function isMapped(address token) external view returns (bool);

    function prepare(uint256 projectTokenAmount, address beneficiary, uint256 minTokensReclaimed, address token)
        external;

    function mapToken(JBTokenMapping calldata map) external;

    function mapTokens(JBTokenMapping[] calldata maps) external;

    function toRemote(address token) external payable;

    event NewInboxTreeRoot(address indexed token, uint64 nonce, bytes32 root);

    event RootToRemote(bytes32 indexed root, address indexed terminalToken, uint256 index, uint64 nonce);

    event Claimed(
        address beneficiary,
        address token,
        uint256 projectTokenAmount,
        uint256 terminalTokenAmount,
        uint256 index,
        bool autoAddedToBalance
    );

    event InsertToOutboxTree(
        address indexed beneficiary,
        address indexed terminalToken,
        bytes32 hashed,
        uint256 index,
        bytes32 root,
        uint256 projectTokenAmount,
        uint256 terminalTokenAmount
    );
}
