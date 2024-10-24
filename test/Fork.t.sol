// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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
import {ICCIPRouter} from "src/interfaces/ICCIPRouter.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {JBTokenMapping} from "../src/structs/JBTokenMapping.sol";
import {JBRemoteToken} from "../src/structs/JBRemoteToken.sol";
import {JBOutboxTree} from "../src/structs/JBOutboxTree.sol";
import {JBInboxTreeRoot} from "../src/structs/JBInboxTreeRoot.sol";
import {JBMessageRoot} from "../src/structs/JBMessageRoot.sol";
import {JBClaim} from "../src/structs/JBClaim.sol";
import {JBAddToBalanceMode} from "../src/enums/JBAddToBalanceMode.sol";
import {MerkleLib} from "../src/utils/MerkleLib.sol";

import "forge-std/Test.sol";
import {JBCCIPSuckerDeployer} from "src/deployers/JBCCIPSuckerDeployer.sol";
import {JBCCIPSucker} from "../src/JBCCIPSucker.sol";
import {BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {JBClaim} from "../src/structs/JBClaim.sol";
import {JBLeaf} from "../src/structs/JBClaim.sol";
import {MerkleLib} from "../src/utils/MerkleLib.sol";
import {CCIPHelper} from "../src/libraries/CCIPHelper.sol";

contract CCIPSuckerForkedTests is TestBaseWorkflow, JBTest {
    // CCIP Local Simulator Contracts
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    BurnMintERC677Helper ccipBnM;
    BurnMintERC677Helper ccipBnMArbSepolia;

    // Re-used parameters for project/ruleset/sucker setups
    JBRulesetMetadata _metadata;
    JBAddToBalanceMode atbMode = JBAddToBalanceMode.ON_CLAIM;

    // Sucker and token
    JBCCIPSuckerDeployer suckerDeployer;
    JBCCIPSuckerDeployer suckerDeployer2;
    IJBSucker suckerGlobal;
    IJBToken projectOneToken;

    // Chain ids and selectors
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    uint64 arbSepoliaChainSelector = 3_478_487_238_524_512_106;
    uint64 ethSepoliaChainSelector = 16_015_286_601_757_825_753;

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

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        Register.NetworkDetails memory sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        ccipBnM = BurnMintERC677Helper(sepoliaNetworkDetails.ccipBnMAddress);
        vm.label(address(ccipBnM), "bnmEthSep");
        vm.makePersistent(address(ccipBnM));
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
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](0);
            // _payoutLimits[0] =
            //     JBCurrencyAmount({amount: 10 * 10 ** 18, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});

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
            JBAccountingContext[] memory _tokensToAccept = new JBAccountingContext[](2);

            _tokensToAccept[0] = JBAccountingContext({
                token: JBConstants.NATIVE_TOKEN,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            _tokensToAccept[1] = JBAccountingContext({
                token: address(ccipBnM),
                decimals: 18,
                currency: uint32(uint160(address(ccipBnM)))
            });

            _terminalConfigurations[0] =
                JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: _tokensToAccept});

            mockExpect(
                address(ccipBnM),
                abi.encodeCall(IERC165.supportsInterface, (type(IERC20Metadata).interfaceId)),
                abi.encode(true)
            );

            // Create a first project to collect fees.
            jbController().launchProjectFor({
                owner: multisig(),
                projectUri: "whatever",
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
                memo: ""
            });

            // Setup an erc20 for the project
            projectOneToken = jbController().deployERC20For(1, "SuckerToken", "SOOK", bytes32(0));

            // Add a price-feed to reconcile pays and redeems with our test token
            MockPriceFeed _priceFeedNativeTest = new MockPriceFeed(100 * 10 ** 18, 18); // 2000 test token == 1 native
                // token
            vm.label(address(_priceFeedNativeTest), "Mock Price Feed Native-ccipBnM");

            vm.startPrank(address(jbController()));
            IJBPrices(jbPrices()).addPriceFeedFor({
                projectId: 1,
                pricingCurrency: uint32(uint160(address(ccipBnM))),
                unitCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
                feed: IJBPriceFeed(_priceFeedNativeTest)
            });
        }
    }

    function initL2AndUtils() public {
        // Create and select our L2 fork- preparing to deploy our project and sucker
        arbSepoliaFork = vm.createSelectFork(ARBITRUM_SEPOLIA_RPC_URL);

        // Get the corresponding remote token and label it for convenience in reading any trace in console
        Register.NetworkDetails memory arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(421_614);

        // This is a faux token helper provided to emulate token bridges of the burn and mint type via CCIP
        ccipBnMArbSepolia = BurnMintERC677Helper(arbSepoliaNetworkDetails.ccipBnMAddress);
        vm.label(address(ccipBnMArbSepolia), "bnmArbSep");
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
            JBAccountingContext[] memory _tokensToAccept = new JBAccountingContext[](2);

            _tokensToAccept[0] = JBAccountingContext({
                token: JBConstants.NATIVE_TOKEN,
                decimals: 18,
                currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
            });

            _tokensToAccept[1] = JBAccountingContext({
                token: address(ccipBnMArbSepolia),
                decimals: 18,
                currency: uint32(uint160(address(ccipBnMArbSepolia)))
            });

            _terminalConfigurations[0] =
                JBTerminalConfig({terminal: jbMultiTerminal(), accountingContextsToAccept: _tokensToAccept});

            mockExpect(
                address(ccipBnMArbSepolia),
                abi.encodeCall(IERC165.supportsInterface, (type(IERC20Metadata).interfaceId)),
                abi.encode(true)
            );

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

        vm.stopPrank();
        vm.startPrank(address(0x1112222));
        suckerDeployer = new JBCCIPSuckerDeployer(jbDirectory(), jbPermissions(), jbTokens(), address(this));
        vm.stopPrank();

        // Set the remote chain as arb-sep, which also grabs the chain selector from CCIPHelper for deployer
        suckerDeployer.setChainSpecificConstants(
            421_614, CCIPHelper.selectorOfChain(421_614), ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
        );

        // deploy our first sucker (on sepolia, the current fork, or "L1").
        suckerGlobal = suckerDeployer.createForSender(1, "salty");
        vm.label(address(suckerGlobal), "suckerGlobal");

        // In-memory vars needed for setup
        // Allow the sucker to mint- This permission array is also used in second project config toward the end of this
        // setup.
        uint8[] memory ids = new uint8[](1);
        ids[0] = JBPermissionIds.MINT_TOKENS;

        // Permissions data for setPermissionsFor().
        JBPermissionsData memory perms =
            JBPermissionsData({operator: address(suckerGlobal), projectId: 1, permissionIds: ids});

        // Chain selectors of remote chains allowed by the suckers (bi-directional in this example).
        uint64[] memory allowedChains = new uint64[](2);
        allowedChains[0] = arbSepoliaChainSelector;
        allowedChains[1] = ethSepoliaChainSelector;

        // Allow our L1 sucker to mint.
        vm.startPrank(multisig());
        jbPermissions().setPermissionsFor(multisig(), perms);

        // Launch and configure our project on L1 (selected fork is still sepolia).
        launchAndConfigureL1Project();

        // Sucker (on L1) now allows our intended chains and L1 setup is complete.
        vm.stopPrank();

        // Init our L2 fork and CCIP Local simulator utils for L2.
        initL2AndUtils();

        // Setup JBV4 on our forked L2 (arb-sep).
        super.setUp();

        vm.stopPrank();

        vm.startPrank(address(0x1112222));
        suckerDeployer2 = new JBCCIPSuckerDeployer(jbDirectory(), jbPermissions(), jbTokens(), address(this));
        vm.stopPrank();

        suckerDeployer2.setChainSpecificConstants(
            11_155_111, CCIPHelper.selectorOfChain(11_155_111), ICCIPRouter(CCIPHelper.routerOfChain(block.chainid))
        );

        // Deploy the sucker on L2.
        suckerDeployer2.createForSender(1, "salty");

        // vm.prank(address(suckerDeployer2));
        // deployCodeTo(
        //     "JBCCIPSucker.sol",
        //     abi.encode(jbDirectory(), jbTokens(), jbPermissions(), address(0), atbMode),
        //     address(suckerGlobal)
        // );

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

    function test_forkNativeTransfer() external {
        // The pool is disabled for now, but functionality was confirmed in past runs.
        vm.skip(true);

        // Declare test actors and parameters
        address rootSender = makeAddr("rootSender");
        address user = makeAddr("him");
        uint256 amountToSend = 100;
        uint256 maxRedeemed = amountToSend / 2;

        // Select our L1 fork to begin this test.
        vm.selectFork(sepoliaFork);

        // Give ourselves test tokens
        vm.deal(user, amountToSend);

        // Map the token
        JBTokenMapping memory map = JBTokenMapping({
            localToken: JBConstants.NATIVE_TOKEN,
            minGas: 200_000,
            remoteToken: JBConstants.NATIVE_TOKEN,
            minBridgeAmount: 1
        });

        vm.prank(multisig());
        suckerGlobal.mapToken(map);

        // Let the terminal spend our test tokens so we can pay and receive project tokens
        vm.startPrank(user);
        // ccipBnM.approve(address(jbMultiTerminal()), amountToSend);

        // receive 500 project tokens as a result
        uint256 projectTokenAmount =
            jbMultiTerminal().pay{value: amountToSend}(1, JBConstants.NATIVE_TOKEN, amountToSend, user, 0, "", "");

        // Approve the sucker to use those project tokens received by the user (we are still pranked as user)
        IERC20(address(projectOneToken)).approve(address(suckerGlobal), projectTokenAmount);

        // Call prepare which uses our project tokens to retrieve (redeem) for our backing tokens (test token)
        suckerGlobal.prepare(projectTokenAmount, user, maxRedeemed, JBConstants.NATIVE_TOKEN);
        vm.stopPrank();

        // Give the root sender some eth to pay the fees
        vm.deal(rootSender, 1 ether);

        // Initiates the bridging
        vm.prank(rootSender);
        suckerGlobal.toRemote{value: 1 ether}(JBConstants.NATIVE_TOKEN);

        // Fees are paid but balance isn't zero (excess msg.value is returned)
        assert(rootSender.balance < 1 ether);
        assert(rootSender.balance > 0);

        // Use CCIP local to initiate the transfer on the L2
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        // Check that the tokens were transferred
        assertEq(address(suckerGlobal).balance, maxRedeemed);

        // This is the most simple verification that messages are being sent and received though
        // Meaning CCIP transferred the data to our sucker on L2's inbox
        bytes32 inboxRoot = suckerGlobal.inboxOf(JBConstants.NATIVE_TOKEN).root;
        assertNotEq(inboxRoot, bytes32(0));
    }

    function test_forkTokenTransfer() external {
        // Declare test actors and parameters
        address rootSender = makeAddr("rootSender");
        address user = makeAddr("him");
        uint256 amountToSend = 100;
        uint256 maxRedeemed = amountToSend / 2;

        // Select our L1 fork to begin this test.
        vm.selectFork(sepoliaFork);

        // Give ourselves test tokens
        ccipBnM.drip(address(user));

        // Map the token
        JBTokenMapping memory map = JBTokenMapping({
            localToken: address(ccipBnM),
            minGas: 200_000,
            remoteToken: address(ccipBnMArbSepolia),
            minBridgeAmount: 1
        });

        vm.prank(multisig());
        suckerGlobal.mapToken(map);

        // Let the terminal spend our test tokens so we can pay and receive project tokens
        vm.startPrank(user);
        ccipBnM.approve(address(jbMultiTerminal()), amountToSend);

        // receive 500 project tokens as a result
        uint256 projectTokenAmount = jbMultiTerminal().pay(1, address(ccipBnM), amountToSend, user, 0, "", "");

        // Approve the sucker to use those project tokens received by the user (we are still pranked as user)
        IERC20(address(projectOneToken)).approve(address(suckerGlobal), projectTokenAmount);

        // Call prepare which uses our project tokens to retrieve (redeem) for our backing tokens (test token)
        suckerGlobal.prepare(projectTokenAmount, user, maxRedeemed, address(ccipBnM));
        vm.stopPrank();

        // Give the root sender some eth to pay the fees
        vm.deal(rootSender, 1 ether);

        // Initiates the bridging
        vm.prank(rootSender);
        suckerGlobal.toRemote{value: 1 ether}(address(ccipBnM));

        // Fees are paid but balance isn't zero (excess msg.value is returned)
        assert(rootSender.balance < 1 ether);
        assert(rootSender.balance > 0);

        // Use CCIP local to initiate the transfer on the L2
        ccipLocalSimulatorFork.switchChainAndRouteMessage(arbSepoliaFork);

        // Check that the tokens were transferred
        assertEq(ccipBnMArbSepolia.balanceOf(address(suckerGlobal)), maxRedeemed);

        // This is the most simple verification that messages are being sent and received though
        // Meaning CCIP transferred the data to our sucker on L2's inbox
        bytes32 inboxRoot = suckerGlobal.inboxOf(address(ccipBnMArbSepolia)).root;
        assertNotEq(inboxRoot, bytes32(0));

        // TODO: Maybe test claiming but it was working in previous version from another repo
        // Setup claim data
        /* JBLeaf memory _leaf = JBLeaf({
            index: 1,
            beneficiary: user,
            projectTokenAmount: projectTokenAmount,
            terminalTokenAmount: maxRedeemed
        });

        // faux proof data for test claim
        bytes32[32] memory _proof;

        JBClaim memory _claimData = JBClaim({token: address(ccipBnMArbSepolia), leaf: _leaf, proof: _proof});

        suckerGlobal.testClaim(_claimData); */
    }
}
