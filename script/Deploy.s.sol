// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../src/deployers/JBOptimismSuckerDeployer.sol";
import "../src/deployers/JBBaseSuckerDeployer.sol";
import "../src/deployers/JBArbitrumSuckerDeployer.sol";
import "../src/deployers/JBCCIPSuckerDeployer.sol";
import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";
import {JBSuckerRegistry} from "./../src/JBSuckerRegistry.sol";
import {ICCIPRouter} from "./../src/interfaces/ICCIPRouter.sol";
import {ARBAddresses} from "../src/libraries/ARBAddresses.sol";
import {ARBChains} from "../src/libraries/ARBChains.sol";
import {CCIPHelper} from "../src/libraries/CCIPHelper.sol";

contract DeployScript is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the addressed of the deployers that will get pre-approved.
    address[] PRE_APPROVED_DEPLOYERS;

    address TRUSTED_FORWARDER;

    /// @notice the nonces that are used to deploy the contracts.
    bytes32 OP_SALT = "_SUCKER_ETH_OP_";
    bytes32 BASE_SALT = "_SUCKER_ETH_BASE_";
    bytes32 ARB_SALT = "_SUCKER_ETH_ARB_";

    bytes32 ARB_BASE_SALT = "_SUCKER_ARB_BASE_";
    bytes32 ARB_OP_SALT = "_SUCKER_ARB_OP_";
    bytes32 OP_BASE_SALT = "_SUCKER_OP_BASE_";

    bytes32 REGISTRY_SALT = "REGISTRY";

    function configureSphinx() public override {
        // TODO: Update to contain JB Emergency Developers
        sphinxConfig.projectName = "nana-suckers";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );

        // We use the same trusted forwarder as the core deployment.
        TRUSTED_FORWARDER = core.controller.trustedForwarder();

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        // Perform the deployments for this chain, then deploy the registry and pre-approve the deployers.
        _optimismSucker();
        _baseSucker();
        _arbitrumSucker();
        _ccipSucker();

        // If the registry is already deployed we don't have to deploy it
        // (and we can't add more pre_approved deployers etc.)
        if (
            !_isDeployed(
                REGISTRY_SALT,
                type(JBSuckerRegistry).creationCode,
                abi.encode(core.directory, core.permissions, safeAddress(), TRUSTED_FORWARDER)
            )
        ) {
            // Deploy the registry and pre-aprove the deployers we just deployed.
            JBSuckerRegistry _registry = new JBSuckerRegistry{salt: REGISTRY_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                initialOwner: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Before transferring ownership to JBDAO we approve the deployers.
            if (PRE_APPROVED_DEPLOYERS.length != 0) {
                _registry.allowSuckerDeployers(PRE_APPROVED_DEPLOYERS);
            }

            // Check what safe this is, if this is the same one as the fee-project owner, then we do not need to
            // transfer. If its not then we transfer to the fee-project safe.
            // NOTE: If this is ran after the configuration of the fee-project, this would transfer it to the
            // REVNET_DEPLOYER. which is *NOT* what we want to happen. In our regular deployment procedure this should
            // never happen though.
            address feeProjectOwner = core.projects.ownerOf(1);
            if (feeProjectOwner != address(0) && feeProjectOwner != safeAddress()) {
                // Transfer ownership to JBDAO.
                _registry.transferOwnership(feeProjectOwner);
            }
        }
    }

    /// @notice handles the deployment and configuration regarding optimism (this also includes the mainnet
    /// configuration).
    function _optimismSucker() internal {
        // Check if this sucker is already deployed on this chain,
        // if that is the case we don't need to do anything else for this chain.
        if (
            _isDeployed(
                OP_SALT,
                type(JBOptimismSuckerDeployer).creationCode,
                abi.encode(core.directory, core.permissions, core.tokens, safeAddress(), TRUSTED_FORWARDER)
            )
        ) return;

        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBOptimismSuckerDeployer _opDeployer = new JBOptimismSuckerDeployer{salt: OP_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _opDeployer.setChainSpecificConstants(
                IOPMessenger(
                    block.chainid == 1
                        ? address(0x25ace71c97B33Cc4729CF772ae268934F7ab5fA1)
                        : address(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef)
                ),
                IOPStandardBridge(
                    block.chainid == 1
                        ? address(0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1)
                        : address(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1)
                )
            );

            // Deploy the singleton instance.
            JBOptimismSucker _singleton = new JBOptimismSucker{salt: OP_SALT}({
                deployer: _opDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _opDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_opDeployer));
        }

        // Check if we should do the L2 portion.
        // OP & OP Sepolia.
        if (block.chainid == 10 || block.chainid == 11_155_420) {
            JBOptimismSuckerDeployer _opDeployer = new JBOptimismSuckerDeployer{salt: OP_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _opDeployer.setChainSpecificConstants(
                IOPMessenger(0x4200000000000000000000000000000000000007),
                IOPStandardBridge(0x4200000000000000000000000000000000000010)
            );

            // Deploy the singleton instance.
            JBOptimismSucker _singleton = new JBOptimismSucker{salt: OP_SALT}({
                deployer: _opDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _opDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_opDeployer));
        }
    }

    /// @notice handles the deployment and configuration regarding base (this also includes the mainnet configuration).
    function _baseSucker() internal {
        // Check if this sucker is already deployed on this chain,
        // if that is the case we don't need to do anything else for this chain.
        if (
            _isDeployed(
                BASE_SALT,
                type(JBBaseSuckerDeployer).creationCode,
                abi.encode(core.directory, core.permissions, core.tokens, safeAddress(), TRUSTED_FORWARDER)
            )
        ) return;

        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBBaseSuckerDeployer _baseDeployer = new JBBaseSuckerDeployer{salt: BASE_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _baseDeployer.setChainSpecificConstants(
                IOPMessenger(
                    block.chainid == 1
                        ? address(0x866E82a600A1414e583f7F13623F1aC5d58b0Afa)
                        : address(0xC34855F4De64F1840e5686e64278da901e261f20)
                ),
                IOPStandardBridge(
                    block.chainid == 1
                        ? address(0x3154Cf16ccdb4C6d922629664174b904d80F2C35)
                        : address(0xfd0Bf71F60660E2f608ed56e1659C450eB113120)
                )
            );

            // Deploy the singleton instance.
            JBBaseSucker _singleton = new JBBaseSucker{salt: BASE_SALT}({
                deployer: _baseDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _baseDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_baseDeployer));
        }

        // Check if we should do the L2 portion.
        // BASE & BASE Sepolia.
        if (block.chainid == 8453 || block.chainid == 84_532) {
            JBBaseSuckerDeployer _baseDeployer = new JBBaseSuckerDeployer{salt: BASE_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _baseDeployer.setChainSpecificConstants(
                IOPMessenger(0x4200000000000000000000000000000000000007),
                IOPStandardBridge(0x4200000000000000000000000000000000000010)
            );

            // Deploy the singleton instance.
            JBBaseSucker _singleton = new JBBaseSucker{salt: BASE_SALT}({
                deployer: _baseDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _baseDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_baseDeployer));
        }
    }

    /// @notice handles the deployment and configuration regarding optimism (this also includes the mainnet
    /// configuration).
    function _arbitrumSucker() internal {
        // Check if this sucker is already deployed on this chain,
        // if that is the case we don't need to do anything else for this chain.
        if (
            _isDeployed(
                ARB_SALT,
                type(JBArbitrumSuckerDeployer).creationCode,
                abi.encode(core.directory, core.permissions, core.tokens, safeAddress(), TRUSTED_FORWARDER)
            )
        ) return;

        // Check if we should do the L1 portion.
        // ETH Mainnet and ETH Sepolia.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            JBArbitrumSuckerDeployer _arbDeployer = new JBArbitrumSuckerDeployer{salt: ARB_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _arbDeployer.setChainSpecificConstants({
                layer: JBLayer.L1,
                inbox: IInbox(block.chainid == 1 ? ARBAddresses.L1_ETH_INBOX : ARBAddresses.L1_SEP_INBOX),
                gatewayRouter: IArbGatewayRouter(
                    block.chainid == 1 ? ARBAddresses.L1_GATEWAY_ROUTER : ARBAddresses.L1_SEP_GATEWAY_ROUTER
                )
            });

            // Deploy the singleton instance.
            JBArbitrumSucker _singleton = new JBArbitrumSucker{salt: ARB_SALT}({
                deployer: _arbDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _arbDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_arbDeployer));
        }

        // Check if we should do the L2 portion.
        // ARB & ARB Sepolia.
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            JBArbitrumSuckerDeployer _arbDeployer = new JBArbitrumSuckerDeployer{salt: ARB_SALT}({
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                configurator: safeAddress(),
                trusted_forwarder: TRUSTED_FORWARDER
            });

            _arbDeployer.setChainSpecificConstants({
                layer: JBLayer.L2,
                inbox: IInbox(address(0)),
                gatewayRouter: IArbGatewayRouter(
                    block.chainid == 42_161 ? ARBAddresses.L2_GATEWAY_ROUTER : ARBAddresses.L2_SEP_GATEWAY_ROUTER
                )
            });

            // Deploy the singleton instance.
            JBArbitrumSucker _singleton = new JBArbitrumSucker{salt: ARB_SALT}({
                deployer: _arbDeployer,
                directory: core.directory,
                permissions: core.permissions,
                tokens: core.tokens,
                addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
                trusted_forwarder: TRUSTED_FORWARDER
            });

            // Configure the deployer to use the singleton instance.
            _arbDeployer.configureSingleton(_singleton);

            PRE_APPROVED_DEPLOYERS.push(address(_arbDeployer));
        }
    }

    function _ccipSucker() internal {
        // Deploy all the L1 suckers.
        if (block.chainid == 1 || block.chainid == 11_155_111) {
            // Optimsim
            PRE_APPROVED_DEPLOYERS.push(
                address(_deployCCIPSuckerFor(OP_SALT, block.chainid == 1 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID))
            );

            // Base
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(BASE_SALT, block.chainid == 1 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID)
                )
            );

            // Arbitrum
            PRE_APPROVED_DEPLOYERS.push(
                address(_deployCCIPSuckerFor(ARB_SALT, block.chainid == 1 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID))
            );
        }

        // Check if we should do the L2 portion.
        // ARB & ARB Sepolia.
        if (block.chainid == 42_161 || block.chainid == 421_614) {
            // L1.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(ARB_SALT, block.chainid == 42_161 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );

            // ARB -> OP.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(ARB_OP_SALT, block.chainid == 42_161 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );

            // ARB -> BASE.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 42_161 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );

            // OP & OP Sepolia.
        } else if (block.chainid == 10 || block.chainid == 11_155_420) {
            // L1.
            PRE_APPROVED_DEPLOYERS.push(
                address(_deployCCIPSuckerFor(OP_SALT, block.chainid == 10 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID))
            );

            // OP -> ARB.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(ARB_OP_SALT, block.chainid == 10 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID)
                )
            );

            // OP -> BASE.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(
                        OP_BASE_SALT, block.chainid == 10 ? CCIPHelper.BASE_ID : CCIPHelper.BASE_SEP_ID
                    )
                )
            );

            // BASE & BASE Sepolia.
        } else if (block.chainid == 8453 || block.chainid == 84_532) {
            // L1.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(BASE_SALT, block.chainid == 8453 ? CCIPHelper.ETH_ID : CCIPHelper.ETH_SEP_ID)
                )
            );

            // BASE -> OP.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(OP_BASE_SALT, block.chainid == 8453 ? CCIPHelper.OP_ID : CCIPHelper.OP_SEP_ID)
                )
            );

            // BASE -> ARB.
            PRE_APPROVED_DEPLOYERS.push(
                address(
                    _deployCCIPSuckerFor(
                        ARB_BASE_SALT, block.chainid == 8453 ? CCIPHelper.ARB_ID : CCIPHelper.ARB_SEP_ID
                    )
                )
            );
        }
    }

    function _deployCCIPSuckerFor(
        bytes32 salt,
        uint256 remoteChainId
    )
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        return _deployCCIPSuckerWith(
            salt,
            core.directory,
            core.permissions,
            core.tokens,
            safeAddress(),
            TRUSTED_FORWARDER,
            remoteChainId,
            // Get the selector of the other side.
            CCIPHelper.selectorOfChain(remoteChainId),
            // Get the router for this side.
            ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
        );
    }

    function _deployCCIPSuckerWith(
        bytes32 salt,
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address configurator,
        address trusted_forwarder,
        uint256 remoteChainId,
        uint64 remoteChainSelector,
        ICCIPRouter router
    )
        internal
        returns (JBCCIPSuckerDeployer deployer)
    {
        deployer = new JBCCIPSuckerDeployer{salt: salt}(directory, permissions, tokens, configurator, trusted_forwarder);

        deployer.setChainSpecificConstants(remoteChainId, remoteChainSelector, router);

        // Deploy the singleton instance.
        JBCCIPSucker singleton = new JBCCIPSucker{salt: salt}({
            deployer: deployer,
            directory: directory,
            tokens: tokens,
            permissions: permissions,
            addToBalanceMode: JBAddToBalanceMode.ON_CLAIM,
            trusted_forwarder: trusted_forwarder
        });

        // Configure the singleton.
        deployer.configureSingleton(singleton);
    }

    function _isDeployed(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory arguments
    )
        internal
        view
        returns (bool)
    {
        address _deployedTo = vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(creationCode, arguments)),
            // Arachnid/deterministic-deployment-proxy address.
            deployer: address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        });

        // Return if code is already present at this address.
        return address(_deployedTo).code.length != 0;
    }
}
