// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import "../../src/JBSucker.sol";

import "../../src/deployers/JBOptimismSuckerDeployer.sol";
import {JBOptimismSucker} from "../../src/JBOptimismSucker.sol";

import "../../src/deployers/JBBaseSuckerDeployer.sol";

import "../../src/deployers/JBCCIPSuckerDeployer.sol";
import {JBCCIPSucker} from "../../src/JBCCIPSucker.sol";

import "../../src/deployers/JBArbitrumSuckerDeployer.sol";
import {JBArbitrumSucker} from "../../src/JBArbitrumSucker.sol";

import {JBLeaf} from "../../src/structs/JBLeaf.sol";
import {JBClaim} from "../../src/structs/JBClaim.sol";
import {JBSuckerDeployerConfig} from "../../src/structs/JBSuckerDeployerConfig.sol";

import {JBProjects} from "@bananapus/core/src/JBProjects.sol";
import {JBDirectory} from "@bananapus/core/src/JBDirectory.sol";
import {JBPermissions} from "@bananapus/core/src/JBPermissions.sol";

import {JBOptimismSuckerDeployer} from "../../src/deployers/JBOptimismSuckerDeployer.sol";
import {JBSuckerRegistry} from "./../../src/JBSuckerRegistry.sol";

contract DeployerTests is Test, TestBaseWorkflow, IERC721Receiver {
    JBSuckerRegistry registry;
    uint256 projectId;

    //*********************************************************************//
    // --------------------------- Setup --------------------------------- //
    //*********************************************************************//

    function setUp() public override {
        // Deploy JB.
        super.setUp();

        // Deploy the registry.
        registry = new JBSuckerRegistry(jbDirectory(), jbPermissions(), address(this));

        // Setup: terminal / project
        // Package up the limits for the given terminal.
        JBRulesetMetadata memory _metadata = JBRulesetMetadata({
            reservedPercent: JBConstants.MAX_RESERVED_PERCENT / 2, //50%
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE, //50%
            baseCurrency: uint32(uint160(address(JBConstants.NATIVE_TOKEN))),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowSetCustomToken: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowSetController: false,
            allowAddAccountingContext: true,
            allowAddPriceFeed: true,
            allowCrosschainSuckerExtension: true,
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForRedemptions: true,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });

        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);

        // Specify a payout limit.
        JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](0);

        // Specify a surplus allowance.
        JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
        _surplusAllowances[0] =
            JBCurrencyAmount({amount: 5 * 10 ** 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});

        _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal()),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: _payoutLimits,
            surplusAllowances: _surplusAllowances
        });

        // Package up the ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
        _rulesetConfigurations[0].mustStartAtOrAfter = 0;
        _rulesetConfigurations[0].duration = 0;
        _rulesetConfigurations[0].weight = 1000 * 10 ** 18;
        _rulesetConfigurations[0].decayPercent = 0;
        _rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));
        _rulesetConfigurations[0].metadata = _metadata;
        _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfigurations[0].fundAccessLimitGroups = _fundAccessLimitGroup;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContext[] memory _tokensToAccept = new JBAccountingContext[](1);

        _tokensToAccept[0] = JBAccountingContext({
            token: JBConstants.NATIVE_TOKEN,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });

        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: _tokensToAccept});

        // Create a first project to collect fees.
        projectId = jbController().launchProjectFor({
            owner: address(this),
            projectUri: "whatever",
            rulesetConfigurations: _rulesetConfigurations,
            terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
            memo: ""
        });

        // Setup an erc20 for the project
        jbController().deployERC20For(1, "SuckerToken", "SOOK", bytes32(0));
    }

    function _setupOptimismDeployer(
        IOPMessenger _opMessenger,
        IOPStandardBridge _opBridge
    )
        internal
        returns (IJBSuckerDeployer deployer)
    {
        JBOptimismSuckerDeployer OPDeployer = new JBOptimismSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this)
        });

        deployer = OPDeployer;
        OPDeployer.configureLayerSpecific(_opMessenger, _opBridge);

        assertEq(address(OPDeployer.opMessenger()), address(_opMessenger));
        assertEq(address(OPDeployer.opBridge()), address(_opBridge));
    }

    function _setupCCIPDeployer(
        uint256 _remoteChainId,
        uint64 _remoteChainSelector,
        ICCIPRouter _ccipRouter
    )
        internal
        returns (IJBSuckerDeployer deployer)
    {
        JBCCIPSuckerDeployer CCIPDeployer = new JBCCIPSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this)
        });

        deployer = CCIPDeployer;
        CCIPDeployer.configureLayerSpecific({
            _remoteChainId: _remoteChainId,
            _remoteChainSelector: _remoteChainSelector,
            _ccipRouter: _ccipRouter
        });

        assertEq(CCIPDeployer.remoteChainId(), _remoteChainId);
        assertEq(CCIPDeployer.remoteChainSelector(), _remoteChainSelector);
        assertEq(address(CCIPDeployer.ccipRouter()), address(_ccipRouter));
    }

    function _setupArbitrumDeployer(
        JBLayer _layer,
        IInbox _inbox,
        IArbGatewayRouter _gatewayRouter
    )
        internal
        returns (IJBSuckerDeployer deployer)
    {
        JBArbitrumSuckerDeployer ARBDeployer = new JBArbitrumSuckerDeployer({
            directory: jbDirectory(),
            permissions: jbPermissions(),
            tokens: jbTokens(),
            configurator: address(this)
        });

        deployer = ARBDeployer;
        ARBDeployer.configureLayerSpecific(_layer, _inbox, _gatewayRouter);

        assertEq(uint256(ARBDeployer.layer()), uint256(_layer));
        assertEq(address(ARBDeployer.inbox()), address(_inbox));
        assertEq(address(ARBDeployer.gatewayRouter()), address(_gatewayRouter));
    }

    //*********************************************************************//
    // ------------------------ Variations ------------------------------- //
    //*********************************************************************//

    function testOPDeployer(IOPMessenger _opMessenger, IOPStandardBridge _opBridge) public {
        IJBSuckerDeployer deployer = _setupOptimismDeployer(_opMessenger, _opBridge);
        IJBSucker sucker = _deployDirectly(deployer, projectId, bytes32(0));
        _assertValidSucker(sucker, projectId);
        _assertOptimismSucker(deployer, sucker);
    }

    function testOPDeployerThroughRegistry(IOPMessenger _opMessenger, IOPStandardBridge _opBridge) public {
        IJBSuckerDeployer deployer = _addToRegistry(_setupOptimismDeployer(_opMessenger, _opBridge));
        _allowMapping(projectId, address(registry));
        IJBSucker sucker = _deployThroughRegistry(deployer, projectId, bytes32(0));
        _assertRegistered(_assertValidSucker(sucker, projectId));
        _assertOptimismSucker(deployer, sucker);
    }

    function testCCIPDeployer(uint256 _remoteChainId, uint64 _remoteChainSelector, ICCIPRouter _ccipRouter) public {
        // Ensure that its not a precompile.
        vm.assume(uint160(address(_ccipRouter)) > 100);

        // We have a sanity check that requires code to be at the router address.
        vm.etch(address(_ccipRouter), "0x1");

        IJBSuckerDeployer deployer = _setupCCIPDeployer(_remoteChainId, _remoteChainSelector, _ccipRouter);
        IJBSucker sucker = _deployDirectly(deployer, projectId, bytes32(0));
        _assertValidSucker(sucker, projectId);
        _assertCCIPSucker(deployer, sucker);
    }

    function testCCIPDeployerThroughRegistry(
        uint256 _remoteChainId,
        uint64 _remoteChainSelector,
        ICCIPRouter _ccipRouter
    )
        public
    {
        // Ensure that its not a precompile.
        vm.assume(uint160(address(_ccipRouter)) > 100);

        // We have a sanity check that requires code to be at the router address.
        vm.etch(address(_ccipRouter), "0x1");

        _allowMapping(projectId, address(registry));
        IJBSuckerDeployer deployer =
            _addToRegistry(_setupCCIPDeployer(_remoteChainId, _remoteChainSelector, _ccipRouter));
        IJBSucker sucker = _deployThroughRegistry(deployer, projectId, bytes32(0));
        _assertRegistered(_assertValidSucker(sucker, projectId));
        _assertCCIPSucker(deployer, sucker);
    }

    function testArbDeployer(bool _layer, IInbox _inbox, IArbGatewayRouter _gatewayRouter) public {
        IJBSuckerDeployer deployer = _setupArbitrumDeployer(_layer ? JBLayer.L1 : JBLayer.L2, _inbox, _gatewayRouter);
        IJBSucker sucker = _deployDirectly(deployer, projectId, bytes32(0));
        _assertValidSucker(sucker, projectId);
        _assertArbSucker(deployer, sucker);
    }

    function testArbDeployerThroughRegistry(bool _layer, IInbox _inbox, IArbGatewayRouter _gatewayRouter) public {
        _allowMapping(projectId, address(registry));
        IJBSuckerDeployer deployer =
            _addToRegistry(_setupArbitrumDeployer(_layer ? JBLayer.L1 : JBLayer.L2, _inbox, _gatewayRouter));
        IJBSucker sucker = _deployThroughRegistry(deployer, projectId, bytes32(0));
        _assertRegistered(_assertValidSucker(sucker, projectId));
        _assertArbSucker(deployer, sucker);
    }

    //*********************************************************************//
    // ------------------------ Utilities ------------------------------- //
    //*********************************************************************//

    function _addToRegistry(IJBSuckerDeployer deployer) internal returns (IJBSuckerDeployer) {
        registry.allowSuckerDeployer(address(deployer));

        // lets us chain calls.
        return deployer;
    }

    function _allowMapping(uint256 _projectId, address beneficiary) internal {
        uint8[] memory permissions = new uint8[](1);
        permissions[0] = JBPermissionIds.MAP_SUCKER_TOKEN;

        jbPermissions().setPermissionsFor(
            address(this),
            JBPermissionsData({operator: beneficiary, projectId: uint56(_projectId), permissionIds: permissions})
        );
    }

    function _allowDeploying(uint256 _projectId, address beneficiary) internal {
        uint8[] memory permissions = new uint8[](1);
        permissions[0] = JBPermissionIds.DEPLOY_SUCKERS;

        jbPermissions().setPermissionsFor(
            address(this),
            JBPermissionsData({operator: beneficiary, projectId: uint56(_projectId), permissionIds: permissions})
        );
    }

    function _deployDirectly(
        IJBSuckerDeployer deployer,
        uint256 _projectId,
        bytes32 salt
    )
        internal
        returns (IJBSucker)
    {
        return deployer.createForSender(_projectId, salt);
    }

    function _deployThroughRegistry(
        IJBSuckerDeployer deployer,
        uint256 _projectId,
        bytes32 salt
    )
        internal
        returns (IJBSucker)
    {
        JBTokenMapping[] memory mappings = new JBTokenMapping[](1);
        mappings[0] = JBTokenMapping({
            localToken: address(JBConstants.NATIVE_TOKEN),
            minGas: 300_000,
            remoteToken: address(JBConstants.NATIVE_TOKEN),
            minBridgeAmount: 0.1 ether
        });

        JBSuckerDeployerConfig[] memory configurations = new JBSuckerDeployerConfig[](1);
        configurations[0] = JBSuckerDeployerConfig({deployer: deployer, mappings: mappings});

        return IJBSucker(registry.deploySuckersFor(_projectId, salt, configurations)[0]);
    }

    //*********************************************************************//
    // -------------------------- Asserts -------------------------------- //
    //*********************************************************************//

    function _assertValidSucker(IJBSucker sucker, uint256 _projectId) internal returns (IJBSucker) {
        assertEq(sucker.PROJECT_ID(), _projectId);
        assertEq(address(sucker.DIRECTORY()), address(jbDirectory()));
        assertEq(address(sucker.TOKENS()), address(jbTokens()));
        assertEq(sucker.PEER(), address(sucker));
        assertEq(uint8(sucker.state()), uint8(JBSuckerState.ENABLED));

        return sucker;
    }

    function _assertRegistered(IJBSucker sucker) internal returns (IJBSucker) {
        uint256 _projectId = sucker.PROJECT_ID();
        assert(registry.isSuckerOf(_projectId, address(sucker)));
        assertEq(address(registry.suckersOf(_projectId)[0]), address(sucker));
        return sucker;
    }

    function _assertOptimismSucker(IJBSuckerDeployer deployer, IJBSucker sucker) internal returns (IJBSucker) {
        assertEq(
            address(JBOptimismSuckerDeployer(address(deployer)).opMessenger()),
            address(JBOptimismSucker(payable(address(sucker))).OPMESSENGER())
        );
        assertEq(
            address(JBOptimismSuckerDeployer(address(deployer)).opBridge()),
            address(JBOptimismSucker(payable(address(sucker))).OPBRIDGE())
        );

        return sucker;
    }

    function _assertCCIPSucker(IJBSuckerDeployer deployer, IJBSucker sucker) internal returns (IJBSucker) {
        assertEq(
            address(JBCCIPSuckerDeployer(address(deployer)).ccipRouter()),
            address(JBCCIPSucker(payable(address(sucker))).CCIP_ROUTER())
        );

        assertEq(
            JBCCIPSuckerDeployer(address(deployer)).remoteChainId(),
            JBCCIPSucker(payable(address(sucker))).REMOTE_CHAIN_ID()
        );

        assertEq(
            JBCCIPSuckerDeployer(address(deployer)).remoteChainSelector(),
            JBCCIPSucker(payable(address(sucker))).REMOTE_CHAIN_SELECTOR()
        );
        return sucker;
    }

    function _assertArbSucker(IJBSuckerDeployer deployer, IJBSucker sucker) internal returns (IJBSucker) {
        assertEq(
            uint256(JBArbitrumSuckerDeployer(address(deployer)).layer()),
            uint256(JBArbitrumSucker(payable(address(sucker))).LAYER())
        );
        assertEq(
            address(JBArbitrumSuckerDeployer(address(deployer)).inbox()),
            address(JBArbitrumSucker(payable(address(sucker))).ARBINBOX())
        );
        assertEq(
            address(JBArbitrumSuckerDeployer(address(deployer)).gatewayRouter()),
            address(JBArbitrumSucker(payable(address(sucker))).GATEWAYROUTER())
        );
        return sucker;
    }

    /// @notice This function is called when we create a JB project.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
