// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {BPOptimismSucker, IJBDirectory, IJBTokens, IJBPermissions} from "../src/BPOptimismSucker.sol";
import {BPSuckerDelegate} from "../src/BPSuckerDelegate.sol";
import {OPMessenger} from "../src/interfaces/OPMessenger.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IJBPermissions, JBPermissionsData} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import "@bananapus/permission-ids/src/JBPermissionIds.sol";
// import "@bananapus/core/src/interfaces/IJBController.sol";
// import "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";
import "@bananapus/core/src/interfaces/terminal/IJBMultiTerminal.sol";
// import "@bananapus/core/src/interfaces/IJBPriceFeed.sol";
// import "@bananapus/core/src/interfaces/IJBPrices.sol";
import "@bananapus/core/src/libraries/JBConstants.sol";
// import "@bananapus/permission-ids/src/JBPermissionIds.sol";
// import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
// import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
// import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
// import {IJBPermissions, JBPermissionsData} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface OPTestBridgeToken is IERC20 {
    function faucet() external;
}

contract PermissionsScript is Script {
    // Sepolia config
    string CHAIN_A_RPC;
    OPMessenger constant CHAIN_A_OP_MESSENGER = OPMessenger(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef);
    string CHAIN_A_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155111/run-latest.json";
    uint256 PROJECT_ID_CHAIN_A = 2;

    // OP Sepolia config
    string CHAIN_B_RPC;
    OPMessenger constant CHAIN_B_OP_MESSENGER = OPMessenger(0x4200000000000000000000000000000000000007);
    string CHAIN_B_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155420/run-latest.json";
    uint256 PROJECT_ID_CHAIN_B = 2;

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
        vm.createSelectFork(CHAIN_B_RPC);
        vm.startBroadcast();

        uint256 _projectIdB = 7;

        OPTestBridgeToken _testToken = OPTestBridgeToken(0x7c6b91D9Be155A6Db01f749217d76fF02A7227F2);
        IJBRedeemTerminal _terminal =
            IJBRedeemTerminal(_getDeploymentAddress(CHAIN_B_DEPLOYMENT_JSON, "JBMultiTerminal"));
        uint256 _amount = 1000_000_000_000_000_000_000;

        _testToken.approve(address(_terminal), _amount);

        // Perform the pay to get added to the tree.
        _terminal.pay({
            projectId: _projectIdB,
            token: address(_testToken),
            amount: _amount,
            beneficiary: msg.sender,
            minReturnedTokens: 0,
            memo: "",
            metadata: bytes("")
        });

        // Send the tree to the L1.
        BPSuckerDelegate(payable(0x0af08A4aa6ebC5D158F634d3D02f1A7193BfD9EB)).toRemote(address(_testToken));
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
