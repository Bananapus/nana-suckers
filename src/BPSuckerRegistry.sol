// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {JBOwnable, IJBProjects, IJBPermissions} from "@bananapus/ownable/src/JBOwnable.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {IBPSucker} from "./interfaces/IBPSucker.sol";
import {IBPSuckerRegistry} from "./interfaces/IBPSuckerRegistry.sol";
import {BPSuckerDeployerConfig} from "./structs/BPSuckerDeployerConfig.sol";

contract BPSuckerRegistry is JBOwnable, IBPSuckerRegistry {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    /// @notice A constant indicating that this sucker exists and belongs to a specific project.
    uint256 constant SUCKER_EXISTS = 1;

    /// @notice Tracks the suckers for the specified project.
    mapping(uint256 => EnumerableMap.AddressToUintMap) _suckersOf;

    /// @notice Tracks whether the specified sucker deployer is approved by this registry.
    mapping(address deployer => bool) public suckerDeployerIsAllowed;

    constructor(IJBProjects projects, IJBPermissions permissions, address _initialOwner)
        JBOwnable(projects, permissions, address(_initialOwner), 0)
    {}

    /// @notice Returns true if the specified sucker belongs to the specified project, and was deployed through this registry.
    /// @param projectId The ID of the project to check for.
    /// @param suckerAddress The address of the sucker to check.
    function isSuckerOf(uint256 projectId, address suckerAddress) external view returns (bool) {
        return _suckersOf[projectId].get(suckerAddress) == SUCKER_EXISTS;
    }

    /// @notice Gets all of the specified project's suckers which were deployed through this registry.
    /// @param projectId The ID of the project to get the suckers of.
    function suckersOf(uint256 projectId) external view returns (address[] memory) {
        return _suckersOf[projectId].keys();
    }

    /// @notice Adds a suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployer The address of the deployer to add.
    function allowSuckerDeployer(address deployer) public override onlyOwner {
        suckerDeployerIsAllowed[deployer] = true;
        emit SuckerDeployerAllowed(deployer);
    }

    /// @notice Adds multiple suckers deployer to the allowlist.
    /// @dev Can only be called by this contract's owner (initially project ID 1, or JuiceboxDAO).
    /// @param deployers The address of the deployer to add.
    function allowSuckerDeployers(address[] calldata deployers) public onlyOwner {
        for (uint256 _i; _i < deployers.length; _i++) {
            suckerDeployerIsAllowed[deployers[_i]] = true;
            emit SuckerDeployerAllowed(deployers[_i]);
        }
    }

    /// @notice Deploy one or more suckers for the specified project.
    /// @dev The caller must be the project's owner or have `JBPermissionIds.DEPLOY_SUCKERS` from the project's owner.
    /// @param projectId The ID of the project to deploy suckers for.
    /// @param salt The salt used to deploy the contract. For the suckers to be peers, this must be the same value on each chain where suckers are deployed.
    /// @param configurations The sucker deployer configs to use to deploy the suckers.
    /// @return suckers The addresses of the deployed suckers.
    function deploySuckersFor(uint256 projectId, bytes32 salt, BPSuckerDeployerConfig[] calldata configurations)
        public
        override
        returns (address[] memory suckers)
    {
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBPermissionIds.DEPLOY_SUCKERS
        });

        if (configurations.length == 0) revert NO_SUCKER_CONFIG();

        // Create an array to store the suckers as they are deployed.
        suckers = new address[](configurations.length);

        // Calculate the salt using the sender's address and the provided `salt`.
        // This means that for suckers to be peers, the sender has to be the same on each chain.
        salt = keccak256(abi.encode(msg.sender, salt));

        // Iterate through the configurations and deploy the suckers.
        for (uint256 i; i < configurations.length; i++) {
            // Make sure the deployer is allowed.
            if (!suckerDeployerIsAllowed[address(configurations[i].deployer)]) {
                revert INVALID_DEPLOYER(address(configurations[i].deployer));
            }

            // Create the sucker.
            IBPSucker sucker = configurations[i].deployer.createForSender({localProjectId: projectId, salt: salt});
            suckers[i] = address(sucker);

            // Store the sucker as being deployed for this project.
            _suckersOf[projectId].set(address(sucker), SUCKER_EXISTS);

            // Map the tokens for the sucker.
            sucker.mapTokens(configurations[i].mappings);
        }

        emit SuckersDeployedFor(projectId, suckers);
    }

    function _emitTransferEvent(address previousOwner, address newOwner, uint88 newProjectId)
        internal
        virtual
        override
    {
        // Only emit after the initial transfer.
        if (address(this).code.length != 0) {
            emit OwnershipTransferred(previousOwner, newProjectId == 0 ? newOwner : PROJECTS.ownerOf(newProjectId));
        }
    }
}
