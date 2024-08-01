// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBPrices} from "@bananapus/core/src/interfaces/IJBPrices.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBRulesets} from "@bananapus/core/src/interfaces/IJBRulesets.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {JBArbitrumSucker} from "../JBArbitrumSucker.sol";
import {JBAddToBalanceMode} from "../enums/JBAddToBalanceMode.sol";
import {IJBSucker} from "./../interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "./../interfaces/IJBSuckerDeployer.sol";

import {ARBAddresses} from "../libraries/ARBAddresses.sol";
import {ARBChains} from "../libraries/ARBChains.sol";
import {JBLayer} from "../enums/JBLayer.sol";
import {IArbGatewayRouter} from "../interfaces/IArbGatewayRouter.sol";

/// @notice An `IJBSuckerDeployerFeeless` implementation to deploy `JBOptimismSucker` contracts.
contract JBArbitrumSuckerDeployer is JBPermissioned, IJBSuckerDeployer {
    error ALREADY_CONFIGURED();

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory immutable DIRECTORY;

    /// @notice The contract that manages token minting and burning.
    IJBTokens immutable TOKENS;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    //*********************************************************************//
    // ---------------- layer specific stored properties ----------------- //
    //*********************************************************************//

    /// @notice The layer that this contract is on.
    JBLayer public immutable LAYER;

    /// @notice Only this address can configure this deployer, can only be used once.
    address immutable LAYER_SPECIFIC_CONFIGURATOR;

    /// @notice A temporary storage slot used by suckers to maintain deterministic deploys.
    uint256 public TEMP_ID_STORE;

    constructor(IJBDirectory directory, IJBTokens tokens, IJBPermissions permissions, address _configurator)
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
        salt = keccak256(abi.encodePacked(msg.sender, salt));

        // Set for a callback to this contract.
        TEMP_ID_STORE = localProjectId;

        sucker = IJBSucker(
            address(
                new JBArbitrumSucker{salt: salt}(DIRECTORY, TOKENS, PERMISSIONS, address(0), JBAddToBalanceMode.MANUAL)
            )
        );

        isSucker[address(sucker)] = true;
    }

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the gateway router address for the current chain
    /// @return gateway for the current chain.
    function gatewayRouter() external view returns (IArbGatewayRouter gateway) {
        uint256 _chainId = block.chainid;
        if (_chainId == ARBChains.ETH_CHAINID) return IArbGatewayRouter(ARBAddresses.L1_GATEWAY_ROUTER);
        if (_chainId == ARBChains.ARB_CHAINID) return IArbGatewayRouter(ARBAddresses.L2_GATEWAY_ROUTER);
        if (_chainId == ARBChains.ETH_SEP_CHAINID) return IArbGatewayRouter(ARBAddresses.L1_SEP_GATEWAY_ROUTER);
        if (_chainId == ARBChains.ARB_SEP_CHAINID) return IArbGatewayRouter(ARBAddresses.L2_SEP_GATEWAY_ROUTER);
    }

    /* /// @notice handles some layer specific configuration that can't be done in the constructor otherwise deployment addresses would change.
    /// @notice messenger the OPMesssenger on this layer.
    /// @notice bridge the OPStandardBridge on this layer.
    function configureLayerSpecific(OPMessenger messenger, OPStandardBridge bridge) external {
        if (address(MESSENGER) != address(0) || address(BRIDGE) != address(0)) {
            revert ALREADY_CONFIGURED();
        }
        // Configure these layer specific properties.
        // This is done in a separate call to make the deployment code chain agnostic.
        MESSENGER = messenger;
        BRIDGE = INBOX.bridge();
    } */
}
