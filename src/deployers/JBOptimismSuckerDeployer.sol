// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";
import {JBOptimismSucker} from "../JBOptimismSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IJBOpSuckerDeployer} from "./../interfaces/IJBOpSuckerDeployer.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";
import {IOPMessenger} from "../interfaces/IOPMessenger.sol";
import {IOPStandardBridge} from "../interfaces/IOPStandardBridge.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBOptimismSuckerDeployer is JBPermissioned, IJBSuckerDeployer, IJBOpSuckerDeployer {
    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable override LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable override TOKENS;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice The singleton used to clone suckers.
    JBOptimismSucker public singleton;

    /// @notice The messenger used to send messages between the local and remote sucker.
    IOPMessenger public override opMessenger;

    /// @notice The bridge used to bridge tokens between the local and remote chain.
    IOPStandardBridge public override opBridge;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public override isSucker;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory The directory of terminals and controllers for projects.
    /// @param permissions The permissions contract for the deployer.
    /// @param tokens The contract that manages token minting and burning.
    /// @param configurator The address of the configurator.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address configurator
    )
        JBPermissioned(permissions)
    {
        if (configurator == address(0)) revert JBSuckerDeployer_ZeroConfiguratorAddress();
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function setChainSpecificConstants(IOPMessenger messenger, IOPStandardBridge bridge) external {
        if (address(opMessenger) != address(0) || address(opBridge) != address(0)) {
            revert JBSuckerDeployer_AlreadyConfigured();
        }

        if (msg.sender != LAYER_SPECIFIC_CONFIGURATOR) {
            revert JBSuckerDeployer_Unauthorized(msg.sender, LAYER_SPECIFIC_CONFIGURATOR);
        }

        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        opMessenger = messenger;
        opBridge = bridge;

        singleton = new JBOptimismSucker({
            directory: DIRECTORY,
            permissions: PERMISSIONS,
            tokens: TOKENS,
            addToBalanceMode: JBAddToBalanceMode.MANUAL
        });
    }

    /// @notice Create a new `JBSucker` for a specific project.
    /// @dev Uses the sender address as the salt, which means the same sender must call this function on both chains.
    /// @param localProjectId The project's ID on the local chain.
    /// @param salt The salt to use for the `create2` address.
    /// @return sucker The address of the new sucker.
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker) {
        // Make sure that this deployer is configured properly.
        if (address(singleton) == address(0)) {
            revert JBSuckerDeployer_DeployerIsNotConfigured();
        }

        // Hash the salt with the sender address to ensure only a specific sender can create this sucker.
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Clone the singleton.
        sucker = IJBSucker(LibClone.cloneDeterministic(address(singleton), salt));

        // Mark it as a sucker that was deployed by this deployer.
        isSucker[address(sucker)] = true;

        // Initialize the clone.
        JBOptimismSucker(payable(address(sucker))).initialize({__peer: address(sucker), __projectId: localProjectId});
    }
}
