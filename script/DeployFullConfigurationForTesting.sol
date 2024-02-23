// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {
    BPOptimismSucker,
    IJBDirectory,
    IJBTokens,
    IJBPermissions,
    BPTokenMapping,
    OPStandardBridge
} from "../src/BPOptimismSucker.sol";
import {BPSuckerDelegate} from "../src/BPSuckerDelegate.sol";
// import {BPOptimismSucker} from "../src/BPOptimismSucker.sol";
import {OPMessenger} from "../src/interfaces/OPMessenger.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@bananapus/core/src/interfaces/IJBController.sol";
import "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";
// import "@bananapus/core/src/interfaces/terminal/IJBMultiTerminal.sol";
// import "@bananapus/core/src/interfaces/IJBPriceFeed.sol";
import "@bananapus/core/src/interfaces/IJBPrices.sol";
import "@bananapus/core/src/libraries/JBConstants.sol";
// import "@bananapus/permission-ids/src/JBPermissionIds.sol";
// import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
// import {IJBPermissions, JBPermissionsData} from "@bananapus/core/src/interfaces/IJBPermissions.sol";

interface OPTestBridgeToken is IERC20 {
    function faucet() external;
}

contract CreateProjectsScript is Script {
    // Sepolia config
    string CHAIN_A_RPC;
    OPMessenger constant CHAIN_A_OP_MESSENGER = OPMessenger(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef);
    OPStandardBridge constant CHAIN_A_OP_BRIDGE = OPStandardBridge(0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1);
    string CHAIN_A_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155111/run-latest.json";

    // OP Sepolia config
    string CHAIN_B_RPC;
    OPMessenger constant CHAIN_B_OP_MESSENGER = OPMessenger(0x4200000000000000000000000000000000000007);
    OPStandardBridge constant CHAIN_B_OP_BRIDGE = OPStandardBridge(0x4200000000000000000000000000000000000010);
    string CHAIN_B_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155420/run-latest.json";

    function setUp() public {
        CHAIN_A_RPC = vm.envString("CHAIN_A_RPC");
        CHAIN_B_RPC = vm.envString("CHAIN_B_RPC");

        if (bytes(CHAIN_A_RPC).length == 0) {
            revert("CHAIN_A_RPC not set.");
        }

        if (bytes(CHAIN_B_RPC).length == 0) {
            revert("CHAIN_B_RPC not set.");
        }
    }

    function run() public {
        // Get the nonces for the two chains.
        uint256 _chainA = vm.createSelectFork(CHAIN_A_RPC);
        uint256 _expectedChainAProjectID =
            IJBProjects(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBProjects")).count() + 1;
        uint256 _chainANonce = vm.getNonce(msg.sender);

        uint256 _chainB = vm.createSelectFork(CHAIN_B_RPC);
        uint256 _expectedChainBProjectID =
            IJBProjects(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBProjects")).count() + 1;
        uint256 _chainBNonce = vm.getNonce(msg.sender);

        if (_chainANonce != _chainANonce) {
            console2.log("WARNING: Nonces do not match between chains.");
        }

        // Compute the addresses for the suckers.
        address _precomputeChainASucker = vm.computeCreateAddress(msg.sender, _chainANonce);
        address _precomputeChainBSucker = vm.computeCreateAddress(msg.sender, _chainBNonce);

        // Deploy the suckers.
        vm.selectFork(_chainA);
        vm.broadcast();
        BPSuckerDelegate _suckerA = new BPOptimismSucker(
            IJBPrices(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBPrices")),
            IJBRulesets(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBRulesets")),
            CHAIN_A_OP_MESSENGER,
            CHAIN_A_OP_BRIDGE,
            IJBDirectory(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBDirectory")),
            IJBTokens(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBTokens")),
            IJBPermissions(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBPermissions")),
            _precomputeChainBSucker,
            _expectedChainAProjectID
        );

        vm.selectFork(_chainB);
        vm.broadcast();
        BPSuckerDelegate _suckerB = new BPOptimismSucker(
            IJBPrices(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBPrices")),
            IJBRulesets(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBRulesets")),
            CHAIN_B_OP_MESSENGER,
            CHAIN_B_OP_BRIDGE,
            IJBDirectory(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBDirectory")),
            IJBTokens(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBTokens")),
            IJBPermissions(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBPermissions")),
            _precomputeChainASucker,
            _expectedChainBProjectID
        );

        // Verify the suckers were deployed to the predetermined addresses.
        if (address(_suckerA) != _precomputeChainASucker) {
            revert("Sucker A was not deployed to the correct address.");
        }
        if (address(_suckerB) != _precomputeChainBSucker) {
            revert("Sucker B was not deployed to the correct address.");
        }

        console2.log("Suckers deployed.");
        console2.log("Sucker A: ", Strings.toHexString(uint160(address(_suckerA)), 20));
        console2.log("Sucker B: ", Strings.toHexString(uint160(address(_suckerB)), 20));

        address[] memory _a_tokens = new address[](1);
        _a_tokens[0] = address(0x12608ff9dac79d8443F17A4d39D93317BAD026Aa);

        address[] memory _b_tokens = new address[](1);
        _b_tokens[0] = address(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2);

        vm.selectFork(_chainA);
        uint256 _projectIdA = _createProject(
            IJBController(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBController")),
            "TestToken",
            "TT",
            IJBRedeemTerminal(_getDeploymentAddress(CHAIN_A_DEPLOYMENT_JSON, "JBMultiTerminal")),
            _a_tokens,
            _suckerA
        );

        console2.log("Chain A projectID ", Strings.toString(_projectIdA));

        vm.selectFork(_chainB);
        uint256 _projectIdB = _createProject(
            IJBController(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBController")),
            "TestTokenOP",
            "TTonOP",
            IJBRedeemTerminal(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBMultiTerminal")),
            _b_tokens,
            _suckerB
        );

        if (_expectedChainAProjectID != _projectIdA) {
            revert("Project ID A is not what we expected it to be.");
        }

        if (_expectedChainBProjectID != _projectIdB) {
            revert("Project ID B is not what we expected it to be.");
        }

        // Configure the suckers.
        vm.selectFork(_chainA);
        vm.broadcast();
        _suckerA.mapToken(
            BPTokenMapping({
                localToken: _a_tokens[0],
                minGas: 200_000,
                remoteToken: _b_tokens[0],
                minBridgeAmount: 0.001 ether
            })
        );

        vm.selectFork(_chainB);
        vm.broadcast();
        _suckerB.mapToken(
            BPTokenMapping({
                localToken: _b_tokens[0],
                minGas: 200_000,
                remoteToken: _a_tokens[0],
                minBridgeAmount: 0.001 ether
            })
        );

        console2.log("Chain B projectID", Strings.toString(_projectIdB));

        vm.selectFork(_chainB);
        OPTestBridgeToken _testToken = OPTestBridgeToken(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2);
        IJBRedeemTerminal _terminal =
            IJBRedeemTerminal(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBMultiTerminal"));
        uint256 _amount = 1000_000_000_000_000_000_000;

        // vm.startBroadcast();

        // // Mint some of the ERC20 token.
        // // _testToken.faucet();
        // // Approve the terminal.
        // _testToken.approve(address(_terminal), _amount);
        // // Pay.
        // _terminal.pay({
        //     projectId: _projectIdB,
        //     token: _b_tokens[0],
        //     amount: _amount,
        //     beneficiary: msg.sender,
        //     minReturnedTokens: 0,
        //     memo: "",
        //     metadata: bytes("")
        // });
        // // Push the root to the remote.
        // _suckerB.toRemote(_b_tokens[0]);

        // vm.stopBroadcast();
    }

    function _createProject(
        IJBController _controller,
        string memory _tokenName,
        string memory _tokenSymbol,
        IJBRedeemTerminal _multiTerminal,
        address[] memory _tokens,
        BPSuckerDelegate _delegate
    ) internal returns (uint256 _projectId) {
        JBRulesetMetadata memory _metadata = JBRulesetMetadata({
            reservedRate: 0,
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
            baseCurrency: uint32(uint160(_tokens[0])),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: true,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalSurplusForRedemptions: false,
            useDataHookForPay: true,
            useDataHookForRedeem: false,
            dataHook: address(_delegate),
            metadata: 0
        });

        // Package up ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].duration = 0;
        _rulesetConfig[0].weight = 10 ** 18;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);

        // Package up terminal configuration.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        _terminalConfigurations[0] = JBTerminalConfig({terminal: _multiTerminal, tokensToAccept: _tokens});

        vm.broadcast();
        _projectId = _controller.launchProjectFor({
            owner: msg.sender,
            projectUri: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        vm.broadcast();
        _controller.deployERC20For(_projectId, _tokenName, _tokenSymbol);
    }

    /**
     * @notice Get the address of a contract that was deployed by the Deploy script.
     *     @dev Reverts if the contract was not found.
     *     @param _path The path to the deployment file.
     *     @param _contractName The name of the contract to get the address of.
     *     @return The address of the contract.
     */
    function _getDeploymentAddress(string memory _path, string memory _contractName) internal view returns (address) {
        string memory _deploymentJson = vm.readFile(_path);
        uint256 _nOfTransactions = stdJson.readStringArray(_deploymentJson, ".transactions").length;

        for (uint256 i = 0; i < _nOfTransactions; i++) {
            string memory _currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
            string memory _currentContractName =
                stdJson.readString(_deploymentJson, string.concat(_currentKey, ".contractName"));

            if (keccak256(abi.encodePacked(_currentContractName)) == keccak256(abi.encodePacked(_contractName))) {
                return stdJson.readAddress(_deploymentJson, string.concat(_currentKey, ".contractAddress"));
            }
        }

        revert(
            string.concat("Could not find contract with name '", _contractName, "' in deployment file '", _path, "'")
        );
    }
}
