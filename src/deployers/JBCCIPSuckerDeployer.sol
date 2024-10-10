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
import {IJBCCIPSuckerDeployer} from "./../interfaces/IJBCCIPSuckerDeployer.sol";
import {ICCIPRouter} from "src/interfaces/ICCIPRouter.sol";

import {LibClone} from "solady/src/utils/LibClone.sol";
import {CCIPHelper} from "src/libraries/CCIPHelper.sol";

/// @notice An `IJBSuckerDeployer` implementation to deploy contracts.
contract JBCCIPSuckerDeployer is JBPermissioned, IJBCCIPSuckerDeployer, IJBSuckerDeployer {
    error JBCCIPSuckerDeployer_DeployerIsNotConfigured();
    error JBCCIPSuckerDeployer_ZeroConfiguratorAddress();
    error JBCCIPSuckerDeployer_InvalidCCIPRouter(address router);
    error JBCCIPSuckerDeployer_Unauthorized();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable TOKENS;

    /// @notice Only this address can configure this deployer, can only be used once.
    address public immutable LAYER_SPECIFIC_CONFIGURATOR;

    //*********************************************************************//
    // ---------------------- public stored properties ------------------- //
    //*********************************************************************//

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    /// @notice The singleton used to clone suckers.
    JBCCIPSucker public singleton;

    /// @notice Store the remote chain id
    uint256 public remoteChainId;

    /// @notice Store the remote chain id
    uint64 public remoteChainSelector;

    /// @notice Store the address of the CCIP router for this chain.
    ICCIPRouter public ccipRouter;

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    constructor(
        IJBDirectory directory,
        IJBTokens tokens,
        IJBPermissions permissions,
        address configurator
    )
        JBPermissioned(permissions)
    {
        LAYER_SPECIFIC_CONFIGURATOR = configurator;
        DIRECTORY = directory;
        TOKENS = tokens;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment
    /// addresses would change.
    function configureLayerSpecific(
        uint256 _remoteChainId,
        uint64 _remoteChainSelector,
        ICCIPRouter _ccipRouter
    )
        external
    {
        // Only allow configurator to set properties - notice we don't restrict reconfiguration here
        // TODO: We now do restrict reconfiguration, we should check why we explicitly commented here that we do not.
        if (msg.sender != LAYER_SPECIFIC_CONFIGURATOR || remoteChainId != 0) {
            revert JBCCIPSuckerDeployer_Unauthorized();
        }

        // Check that the ccipRouter address has code.
        // Its easy to assume `ccipRouter` should be for the remoteChain, but it should be for the localChain.
        if (address(_ccipRouter).code.length == 0) {
            revert JBCCIPSuckerDeployer_InvalidCCIPRouter(address(_ccipRouter));
        }

        remoteChainId = _remoteChainId;
        remoteChainSelector = _remoteChainSelector;
        ccipRouter = _ccipRouter;

        singleton = new JBCCIPSucker({
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
    function createForSender(
        uint256 localProjectId,
        bytes32 salt
    )
        external
        override(IJBCCIPSuckerDeployer, IJBSuckerDeployer)
        returns (IJBSucker sucker)
    {
        // Make sure that this deployer is configured properly.
        if (address(singleton) == address(0)) {
            revert JBCCIPSuckerDeployer_DeployerIsNotConfigured();
        }

        // Hash the salt with the sender address to ensure only a specific sender can create this sucker.
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Clone the singleton.
        sucker = IJBSucker(LibClone.cloneDeterministic(address(singleton), salt));

        // Initialize the clone.
        JBCCIPSucker(payable(address(sucker))).initialize({peer: address(sucker), projectId: localProjectId});

        // Mark it as a sucker that was deployed by this deployer.
        isSucker[address(sucker)] = true;
    }
}
