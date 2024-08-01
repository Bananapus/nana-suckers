// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import /* {*} from */ "@bananapus/core/test/helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from "@bananapus/core/test/mock/MockPriceFeed.sol";
import {IJBSucker} from "../src/interfaces/IJBSucker.sol";
import {IJBSuckerDeployer} from "../src/interfaces/IJBSuckerDeployer.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBTokens} from "@bananapus/core/src/interfaces/IJBTokens.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBPermissioned} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {JBTokenMapping} from "../src/structs/JBTokenMapping.sol";
import {JBRemoteToken} from "../src/structs/JBRemoteToken.sol";
import {JBOutboxTree} from "../src/structs/JBOutboxTree.sol";
import {JBInboxTreeRoot} from "../src/structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "../src/structs/JBMessageRoot.sol";
import {JBClaim} from "../src/structs/JBClaim.sol";
import {JBAddToBalanceMode} from "../src/enums/JBAddToBalanceMode.sol";
import {MerkleLib} from "../src/utils/MerkleLib.sol";

import {JBClaim} from "../src/structs/JBClaim.sol";
import {JBLeaf} from "../src/structs/JBClaim.sol";
import {MerkleLib} from "../src/utils/MerkleLib.sol";

import {JBArbitrumSuckerDeployer} from "src/deployers/JBArbitrumSuckerDeployer.sol";

contract ArbSuckerDeployForkedTests is TestBaseWorkflow, JBTest {
    // Re-used parameters for project/ruleset/sucker setups
    JBRulesetMetadata _metadata;

    // Sucker and token
    JBArbitrumSuckerDeployer suckerDeployer;
    JBArbitrumSuckerDeployer suckerDeployer2;
    IJBSucker suckerOne;
    IJBSucker suckerTwo;
    IJBToken projectOneToken;

    // Chain ids and selectors
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    // RPCs
    string ETHEREUM_SEPOLIA_RPC_URL = vm.envOr("RPC_ETHEREUM_SEPOLIA", string("https://1rpc.io/sepolia"));
    string ARBITRUM_SEPOLIA_RPC_URL =
        vm.envOr("RPC_ARBITRUM_SEPOLIA", string("https://arbitrum-sepolia.blockpi.network/v1/rpc/public"));

    //*********************************************************************//
    // ---------------------------- Setup parts -------------------------- //
    //*********************************************************************//

    function initL1AndUtils() public {
        // Setup starts on sepolia fork
        sepoliaFork = vm.createSelectFork(ETHEREUM_SEPOLIA_RPC_URL);
    }

    function initMetadata() public {
        _metadata = JBRulesetMetadata({
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
            ownerMustSendPayouts: false,
            holdFees: false,
            useTotalSurplusForRedemptions: true,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    function launchAndConfigureL1Project() public {
        // Setup: terminal / project
        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] =
                JBCurrencyAmount({amount: 10 * 10 ** 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});

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
        }

        {
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
            jbController().launchProjectFor({
                owner: multisig(),
                projectUri: "whatever",
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
                memo: ""
            });
        }
    }

    function initL2AndUtils() public {
        // Create and select our L2 fork- preparing to deploy our project and sucker
        arbSepoliaFork = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL);
    }

    function launchAndConfigureL2Project() public {
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
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
            jbController().launchProjectFor({
                owner: multisig(),
                projectUri: "whatever",
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
                memo: ""
            });
        }
    }

    //*********************************************************************//
    // ------------------------------- Setup ----------------------------- //
    //*********************************************************************//

    function setUp() public override {
        // Create (and select) Sepolia fork and make simulator helper contracts persistent.
        initL1AndUtils();

        // Set metadata for the test projects to use.
        initMetadata();

        // run setup on our first fork (sepolia) so we have a JBV4 setup (deploys v4 contracts).
        super.setUp();

        // Mimics JBV4 deployment across all forks in this env.
        vm.makePersistent(address(jbDirectory()));
        vm.makePersistent(address(jbTokens()));
        vm.makePersistent(address(jbPermissions()));
        vm.makePersistent(address(jbMultiTerminal()));
        vm.makePersistent(address(jbController()));
        vm.makePersistent(address(jbProjects()));
        vm.makePersistent(address(jbPrices()));
        vm.makePersistent(address(jbSplits()));
        vm.makePersistent(address(jbAccessConstraintStore()));
        vm.makePersistent(address(jbFeelessAddresses()));
        vm.makePersistent(address(jbTerminalStore()));
        vm.makePersistent(address(jbRulesets()));

        vm.stopPrank();
        suckerDeployer =
            new JBArbitrumSuckerDeployer{salt: "salty"}(jbDirectory(), jbTokens(), jbPermissions(), address(this));

        // deploy our first sucker (on sepolia, the current fork, or "L1").
        suckerOne = suckerDeployer.createForSender(1, "salty");
        vm.label(address(suckerOne), "suckerOne");

        // In-memory vars needed for setup
        // Allow the sucker to mint- This permission array is also used in second project config toward the end of this setup.
        uint8[] memory ids = new uint8[](1);
        ids[0] = JBPermissionIds.MINT_TOKENS;

        // Permissions data for setPermissionsFor().
        JBPermissionsData memory perms =
            JBPermissionsData({operator: address(suckerOne), projectId: 1, permissionIds: ids});

        // Allow our L1 sucker to mint.
        vm.startPrank(multisig());
        jbPermissions().setPermissionsFor(multisig(), perms);

        // Launch and configure our project on L1 (selected fork is still sepolia).
        launchAndConfigureL1Project();

        // Sucker (on L1) now allows our intended chains and L1 setup is complete.
        vm.stopPrank();

        // Init our L2 fork and CCIP Local simulator utils for L2.
        initL2AndUtils();

        vm.stopPrank();
        suckerDeployer2 =
            new JBArbitrumSuckerDeployer{salt: "salty"}(jbDirectory(), jbTokens(), jbPermissions(), address(this));

        suckerTwo = suckerDeployer2.createForSender(1, "salty");
        vm.label(address(suckerTwo), "suckerTwo");

        // Launch our project on L2.
        vm.startPrank(multisig());
        launchAndConfigureL2Project();

        // Allow the L2 sucker to mint.
        jbPermissions().setPermissionsFor(multisig(), perms);

        // Enable intended chains for the L2 Sucker
        vm.stopPrank();
    }

    //*********************************************************************//
    // ------------------------------- Tests ----------------------------- //
    //*********************************************************************//

    function test_addresses_match() external {
        assertEq(address(suckerDeployer), address(suckerDeployer2));
        assertEq(address(suckerOne), address(suckerTwo));
    }
}
