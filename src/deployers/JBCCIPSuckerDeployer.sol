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

/// @notice An `IJBSuckerDeployer` implementation to deploy contracts.
contract JBCCIPSuckerDeployer is JBPermissioned, IJBSuckerDeployer {
    error ONLY_ADMIN();
    error ALREADY_CONFIGURED();
    error NOT_CONFIGURED();

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable TOKENS;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    /// @notice A temporary storage slot used by suckers to maintain deterministic deploys.
    uint256 public TEMP_ID_STORE;

    /// @notice Store the remote chain id
    uint256 public REMOTE_CHAIN_ID;

    /// @notice Store the remote chain id
    uint64 public REMOTE_CHAIN_SELECTOR;

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address _configurator
    )
        JBPermissioned(permissions)
    {
        LAYER_SPECIFIC_CONFIGURATOR = _configurator;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker) {
        // Check layer specific properties first
        if (REMOTE_CHAIN_ID == 0 || REMOTE_CHAIN_SELECTOR == 0) revert NOT_CONFIGURED();

        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set for a callback to this contract.
        TEMP_ID_STORE = localProjectId;

        sucker = IJBSucker(
            address(new JBCCIPSucker{salt: salt}(DIRECTORY, TOKENS, PERMISSIONS, address(0), JBAddToBalanceMode.MANUAL))
        );

        // TODO: See if resetting this value is cheaper than deletion
        // Delete after callback should complete.
        /* delete TEMP_ID_STORE; */

        isSucker[address(sucker)] = true;
    }

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    function configureLayerSpecific(uint256 remoteChainId) external {
        // Only allow configurator to set properties - notice we don't restrict reconfiguration here
        if (msg.sender != LAYER_SPECIFIC_CONFIGURATOR) revert ONLY_ADMIN();

        REMOTE_CHAIN_ID = remoteChainId;
        REMOTE_CHAIN_SELECTOR = CCIPHelper.selectorOfChain(remoteChainId);
    }

    function tempStoreId() external view returns (uint256) {
        return TEMP_ID_STORE;
    }
}
