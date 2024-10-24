// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";
import {JBArbitrumSucker} from "../JBArbitrumSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {JBLayer} from "../enums/JBLayer.sol";
import {IArbGatewayRouter} from "../interfaces/IArbGatewayRouter.sol";
import "../interfaces/IJBArbitrumSuckerDeployer.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";
import {ARBAddresses} from "../libraries/ARBAddresses.sol";
import {ARBChains} from "../libraries/ARBChains.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBArbitrumSuckerDeployer is JBPermissioned, IJBSuckerDeployer, IJBArbitrumSuckerDeployer {
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

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public override isSucker;

    /// @notice The singleton used to clone suckers.
    JBArbitrumSucker public singleton;

    /// @notice The layer that this contract is on.
    JBLayer public arbLayer;

    /// @notice The inbox used to send messages between the local and remote sucker.
    IInbox public override arbInbox;

    /// @notice The gateway router for the specific chain
    IArbGatewayRouter public override arbGatewayRouter;

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
        DIRECTORY = directory;
        TOKENS = tokens;
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function setChainSpecificConstants(JBLayer layer, IInbox inbox, IArbGatewayRouter gatewayRouter) external {
        if (
            uint256(arbLayer) != uint256(0) || address(arbInbox) != address(0)
                || address(arbGatewayRouter) != address(0)
        ) {
            revert JBSuckerDeployer_AlreadyConfigured();
        }

        if (msg.sender != LAYER_SPECIFIC_CONFIGURATOR) {
            revert JBSuckerDeployer_Unauthorized(msg.sender, LAYER_SPECIFIC_CONFIGURATOR);
        }

        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        arbLayer = layer;
        arbInbox = inbox;
        arbGatewayRouter = gatewayRouter;

        singleton = new JBArbitrumSucker({
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
        JBArbitrumSucker(payable(address(sucker))).initialize({__peer: address(sucker), __projectId: localProjectId});
    }
}
