// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {JBRuleset} from "@bananapus/core/src/structs/JBRuleset.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import {IJBSucker} from "./interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./interfaces/IJBSuckerDeployer.sol";
import {IJBSuckerRegistry} from "./interfaces/IJBSuckerRegistry.sol";
import {JBSuckerDeployerConfig} from "./structs/JBSuckerDeployerConfig.sol";
import {JBSuckersPair} from "./structs/JBSuckersPair.sol";
import {JBSuckerState} from "./enums/JBSuckerState.sol";

contract JBSuckerRegistry is Ownable, JBPermissioned, IJBSuckerRegistry {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSuckerRegistry_InvalidDeployer(IJBSuckerDeployer deployer);
    error JBSuckerRegistry_RulesetDoesNotAllowAddingSucker(uint256 projectId);
    error JBSuckerRegistry_SuckerDoesNotBelongToProject(uint256 projectId, address sucker);
    error JBSuckerRegistry_SuckerIsNotDeprecated(address sucker, JBSuckerState suckerState);

    //*********************************************************************//
    // ------------------------- internal constants ----------------------- //
    //*********************************************************************//

    /// @notice A constant indicating that this sucker exists and belongs to a specific project.
    uint256 internal constant _SUCKER_EXISTS = 1;

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The juicebox directory.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice A contract which mints ERC-721s that represent project ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice Tracks whether the specified sucker deployer is approved by this registry.
    /// @custom:member deployer The address of the deployer to check.
    mapping(address deployer => bool) public override suckerDeployerIsAllowed;

    //*********************************************************************//
    // --------------------- internal stored properties ------------------- //
    //*********************************************************************//

    /// @notice Tracks the suckers for the specified project.
    mapping(uint256 => EnumerableMap.AddressToUintMap) internal _suckersOf;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param directory The juicebox directory.
    /// @param permissions A contract storing permissions.
    /// @param initialOwner The initial owner of this contract.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        address initialOwner
    )
        JBPermissioned(permissions)
        Ownable(initialOwner)
    {
        DIRECTORY = directory;
        PROJECTS = directory.PROJECTS();
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Returns true if the specified sucker belongs to the specified project, and was deployed through this
    /// registry.
    /// @param projectId The ID of the project to check for.
    /// @param addr The address of the sucker to check.
    /// @return flag A flag indicating if the sucker belongs to the project, and was deployed through this registry.
    function isSuckerOf(uint256 projectId, address addr) external view override returns (bool) {
        (bool exists, uint256 val) = _suckersOf[projectId].tryGet(addr);
        return exists && val == _SUCKER_EXISTS;
    }

    /// @notice Helper function for retrieving the projects suckers and their metadata.
    /// @param projectId The ID of the project to get the suckers of.
    /// @return pairs The pairs of suckers and their metadata.
    function getSuckerPairs(uint256 projectId) external view returns (JBSuckersPair[] memory pairs) {
        // Get the suckers of the project.
        address[] memory suckers = _suckersOf[projectId].keys();

        // Keep a reference to the number of suckers.
        uint256 numberOfSuckers = suckers.length;

        // Initialize the array of pairs.
        pairs = new JBSuckersPair[](numberOfSuckers);

        // Populate the array of pairs.
        for (uint256 i; i < numberOfSuckers; i++) {
            // Get the sucker being iterated over.
            IJBSucker sucker = IJBSucker(suckers[i]);

            // slither-disable-next-line calls-loop
            pairs[i] =
                JBSuckersPair({local: address(sucker), remote: sucker.PEER(), remoteChainId: sucker.peerChainId()});
        }
    }

    /// @notice Gets all of the specified project's suckers which were deployed through this registry.
    /// @param projectId The ID of the project to get the suckers of.
    /// @return suckers The addresses of the suckers.
    function suckersOf(uint256 projectId) external view override returns (address[] memory) {
        return _suckersOf[projectId].keys();
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Adds a suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployer The address of the deployer to add.
    function allowSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = true;
        emit SuckerDeployerAllowed({deployer: deployer, caller: msg.sender});
    }

    /// @notice Adds multiple suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployers The address of the deployer to add.
    function allowSuckerDeployers(address[] calldata deployers) public onlyOwner {
        // Keep a reference to the number of deployers.
        uint256 numberOfDeployers = deployers.length;

        // Iterate through the deployers and allow them.
        for (uint256 i; i < numberOfDeployers; i++) {
            // Get the deployer being iterated over.
            address deployer = deployers[i];

            // Allow the deployer.
            suckerDeployerIsAllowed[deployer] = true;
            emit SuckerDeployerAllowed({deployer: deployer, caller: msg.sender});
        }
    }

    /// @notice Removes a sucker deployer from the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployer The address of the deployer to remove.
    function removeSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = false;
        emit SuckerDeployerRemoved({deployer: deployer, caller: msg.sender});
    }

    /// @notice Deploy one or more suckers for the specified project.
    /// @dev The caller must be the project's owner or have `JBPermissionIds.DEPLOY_SUCKERS` from the project's owner.
    /// @param projectId The ID of the project to deploy suckers for.
    /// @param salt The salt used to deploy the contract. For the suckers to be peers, this must be the same value on
    /// each chain where suckers are deployed.
    /// @param configurations The sucker deployer configs to use to deploy the suckers.
    /// @return suckers The addresses of the deployed suckers.
    function deploySuckersFor(
        uint256 projectId,
        bytes32 salt,
        JBSuckerDeployerConfig[] calldata configurations
    )
        public
        override
        returns (address[] memory suckers)
    {
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.DEPLOY_SUCKERS
        });

        // Check if the ruleset allows adding a sucker.
        _requireRulesetAllowsAddingSucker({projectId: projectId});

        // Create an array to store the suckers as they are deployed.
        suckers = new address[](configurations.length);

        // Calculate the salt using the sender's address and the provided `salt`.
        // This means that for suckers to be peers, the sender has to be the same on each chain.
        salt = keccak256(abi.encode(msg.sender, salt));

        // Keep a reference to the number of configurations.
        uint256 numberOfConfigurations = configurations.length;

        // Iterate through the configurations and deploy the suckers.
        for (uint256 i; i < numberOfConfigurations; i++) {
            // Get the configuration being iterated over.
            JBSuckerDeployerConfig memory configuration = configurations[i];

            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configuration.deployer)]) {
                revert JBSuckerRegistry_InvalidDeployer(configuration.deployer);
            }

            // Create the sucker.
            // slither-disable-next-line reentrancy-event,calls-loop
            IJBSucker sucker = configuration.deployer.createForSender({localProjectId: projectId, salt: salt});
            suckers[i] = address(sucker);

            // Store the sucker as being deployed for this project.
            // slither-disable-next-line unused-return
            _suckersOf[projectId].set({key: address(sucker), value: _SUCKER_EXISTS});

            // Map the tokens for the sucker.
            // slither-disable-next-line reentrancy-events,calls-loop
            sucker.mapTokens(configuration.mappings);
            emit SuckerDeployedFor({
                projectId: projectId,
                sucker: address(sucker),
                configuration: configuration,
                caller: msg.sender
            });
        }
    }

    /// @notice Lets anyone remove a deprecated sucker from a project.
    /// @param projectId The ID of the project to remove the sucker from.
    /// @param sucker The address of the deprecated sucker to remove.
    function removeDeprecatedSucker(uint256 projectId, address sucker) public {
        // Sanity check, make sure that the sucker does actually belong to the project.
        (bool belongsToProject, uint256 val) = _suckersOf[projectId].tryGet(sucker);
        if (!belongsToProject || val != _SUCKER_EXISTS) {
            revert JBSuckerRegistry_SuckerDoesNotBelongToProject(projectId, address(sucker));
        }

        // Check if the sucker is deprecated.
        JBSuckerState state = IJBSucker(sucker).state();
        if (state != JBSuckerState.DEPRECATED) {
            revert JBSuckerRegistry_SuckerIsNotDeprecated(address(sucker), state);
        }

        // Remove the sucker from the registry.
        _suckersOf[projectId].remove(address(sucker));
        emit SuckerDeprecated({projectId: projectId, sucker: address(sucker), caller: msg.sender});
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Checks if the current ruleset allows adding a sucker.
    /// @dev Reverts if the ruleset does not allow adding a sucker.
    /// @param projectId The ID of the project to check.
    function _requireRulesetAllowsAddingSucker(uint256 projectId) internal view {
        // Get the controller of the project.
        IJBController controller = IJBController(address(DIRECTORY.controllerOf(projectId)));

        // Get the ruleset metadata of the project.
        // slither-disable-next-line unused-return
        (JBRuleset memory ruleset, JBRulesetMetadata memory metadata) = controller.currentRulesetOf(projectId);

        // Check if this transaction is a deployment.
        // TODO: Reconsider if we should handle it this way before the first ruleset.
        bool isDeployment = false;
        if (ruleset.id == 0) {
            (ruleset,) = controller.upcomingRulesetOf(projectId);

            if (ruleset.id == block.timestamp) {
                isDeployment = true;
            }
        }

        // Check if the ruleset allows adding a sucker and that this is *not* the deployment transaction.
        if (!isDeployment && !metadata.allowCrosschainSuckerExtension) {
            revert JBSuckerRegistry_RulesetDoesNotAllowAddingSucker(projectId);
        }
    }
}
