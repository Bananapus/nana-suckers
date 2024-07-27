// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {JBCCIPSucker} from "../JBCCIPSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";

import {CCIPHelper} from "src/libraries/CCIPHelper.sol";

/// @notice An `IJBSuckerDeployer` which deploys `JBCCIPSucker` contracts.
contract JBCCIPSuckerDeployer is JBPermissioned, IJBSuckerDeployer {
    error ADMIN_MUST_SET_CONSTANTS();
    error CONSTANTS_NOT_SET();

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable TOKENS;

    /// @notice The address which is allowed to set chain-specific constants (the remote chain ID and CCIP selector).
    address immutable ADMIN_TO_SET_CONSTANTS;

    /// @notice A mapping storing the addresses of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    /// @notice Temporarily stores the project ID for the sucker being deployed.
    /// @dev The sucker's constructor reads this value to get the project ID while keeping its deployment address deterministic.
    uint256 public TEMP_PROJECT_ID;

    /// @notice The remote chain ID for all suckers deployed by this contract.
    uint256 public REMOTE_CHAIN_ID;

    /// @notice The CCIP selector (a CCIP-specific ID) for the remote chain.
    /// @dev To find a chain's CCIP selector, see [CCIP Supported Networks](https://docs.chain.link/ccip/supported-networks).
    uint64 public REMOTE_CHAIN_SELECTOR;

    constructor(IJBDirectory directory, IJBTokens tokens, IJBPermissions permissions, address _admin)
        JBPermissioned(permissions)
    {
        ADMIN_TO_SET_CONSTANTS = _admin;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    /// @notice Create a new `JBCCIPSucker` for a project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt for the `create2` address.
    /// @return sucker The new sucker's address.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker) {
        // If the chain-specific constants have not been set, revert.
        if (REMOTE_CHAIN_ID == 0 || REMOTE_CHAIN_SELECTOR == 0) revert CONSTANTS_NOT_SET();

        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set the `TEMP_PROJECT_ID` for the sucker's constructor to read.
        TEMP_PROJECT_ID = localProjectId;

        sucker = IJBSucker(
            address(new JBCCIPSucker{salt: salt}(DIRECTORY, TOKENS, PERMISSIONS, address(0), JBAddToBalanceMode.MANUAL))
        );

        // TODO: See if resetting this value is cheaper than deletion
        // Clear the `TEMP_PROJECT_ID` after the sucker is deployed.
        /* delete TEMP_PROJECT_ID; */

        isSucker[address(sucker)] = true;
    }

    /// @notice Sets chain-specific constants – the chain ID and CCIP selector for the remote chain.
    /// @dev Chain-specific constants can only be set by the admin address specified in the constructor.
    /// @dev These constants are set after deployment to ensure deployment addresses match across chains.
    /// @param remoteChainId The ID of the remote chain to connect with.
    function setChainSpecificConstants(uint256 remoteChainId) external {
        // Only allow the pre-specified admin to set these constants.
        if (msg.sender != ADMIN_TO_SET_CONSTANTS) revert ADMIN_MUST_SET_CONSTANTS();

        REMOTE_CHAIN_ID = remoteChainId;
        REMOTE_CHAIN_SELECTOR = CCIPHelper.selectorOfChain(remoteChainId);
    }
}
