// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {BPOptimismSucker, IJBDirectory, IJBTokens, IJBPermissions, BPSucker} from "../src/BPOptimismSucker.sol";
// import {BPSuckQueueItem} from "../src/structs/BPSuckQueueItem.sol";
import {BPSuckerDelegate} from "../src/BPSuckerDelegate.sol";
import {BPLeaf} from "../src/structs/BPLeaf.sol";
import {BPClaim} from "../src/structs/BPClaim.sol";
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

contract ExecuteOnL1Script is Script {
    // Sepolia config
    string CHAIN_A_RPC;
    OPMessenger constant CHAIN_A_OP_MESSENGER = OPMessenger(0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef);
    string CHAIN_A_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155111/run-latest.json";
    uint256 PROJECT_ID_CHAIN_A = 2;

    // OP Sepolia config
    string CHAIN_B_RPC;
    OPMessenger constant CHAIN_B_OP_MESSENGER = OPMessenger(0x4200000000000000000000000000000000000007);
    string CHAIN_B_DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155420/run-latest.json";
    uint256 PROJECT_ID_CHAIN_B = 1;

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
        vm.createSelectFork(CHAIN_A_RPC);

        // BPSuckBridgeItem[] memory _items = new BPSuckBridgeItem[](1);
        // _items[0] = BPSuckBridgeItem({
        //     beneficiary: 0xbA5eD1A8074e23dbeAA2764fc46cd0d172AD9A08,
        //     projectTokens: 50_000
        // });

        /// @notice Claims project tokens for a user.
        // /// @param _token the redemption token that was used.
        // /// @param _leaf information regarding the redemption.
        // /// @param _proof the proof that shows the redemption as being in the smt.
        // function claim(
        //     address _token,
        //     BPLeaf calldata _leaf,
        //     bytes32[TREE_DEPTH] calldata _proof
        // )

        //   uint256 index;
        // address beneficiary;
        // uint256 projectTokenAmount;
        // uint256 terminalTokenAmount;

        bytes32[32] memory _proofArr = abi.decode(
            abi.encode(
                [
                    0x0000000000000000000000000000000000000000000000000000000000000000,
                    0xad3228b676f7d3cd4284a5443f17f1962b36e491b30a40b2405849e597ba5fb5,
                    0xb4c11951957c6f8f642c4af61cd6b24640fec6dc7fc607ee8206a99e92410d30,
                    0x21ddb9a356815c3fac1026b6dec5df3124afbadb485c9ba5a3e3398a04b7ba85,
                    0xe58769b32a1beaf1ea27375a44095a0d1fb664ce2dd358e7fcbfb78c26a19344,
                    0x0eb01ebfc9ed27500cd4dfc979272d1f0913cc9f66540d7e8005811109e1cf2d,
                    0x887c22bd8750d34016ac3c66b5ff102dacdd73f6b014e710b51e8022af9a1968,
                    0xffd70157e48063fc33c97a050f7f640233bf646cc98d9524c6b92bcf3ab56f83,
                    0x9867cc5f7f196b93bae1e27e6320742445d290f2263827498b54fec539f756af,
                    0xcefad4e508c098b9a7e1d8feb19955fb02ba9675585078710969d3440f5054e0,
                    0xf9dc3e7fe016e050eff260334f18a5d4fe391d82092319f5964f2e2eb7c1c3a5,
                    0xf8b13a49e282f609c317a833fb8d976d11517c571d1221a265d25af778ecf892,
                    0x3490c6ceeb450aecdc82e28293031d10c7d73bf85e57bf041a97360aa2c5d99c,
                    0xc1df82d9c4b87413eae2ef048f94b4d3554cea73d92b0f7af96e0271c691e2bb,
                    0x5c67add7c6caf302256adedf7ab114da0acfe870d449a3a489f781d659e8becc,
                    0xda7bce9f4e8618b6bd2f4132ce798cdc7a60e7e1460a7299e3c6342a579626d2,
                    0x2733e50f526ec2fa19a22b31e8ed50f23cd1fdf94c9154ed3a7609a2f1ff981f,
                    0xe1d3b5c807b281e4683cc6d6315cf95b9ade8641defcb32372f1c126e398ef7a,
                    0x5a2dce0a8a7f68bb74560f8f71837c2c2ebbcbf7fffb42ae1896f13f7c7479a0,
                    0xb46a28b6f55540f89444f63de0378e3d121be09e06cc9ded1c20e65876d36aa0,
                    0xc65e9645644786b620e2dd2ad648ddfcbf4a7e5b1a3a4ecfe7f64667a3f0b7e2,
                    0xf4418588ed35a2458cffeb39b93d26f18d2ab13bdce6aee58e7b99359ec2dfd9,
                    0x5a9c16dc00d6ef18b7933a6f8dc65ccb55667138776f7dea101070dc8796e377,
                    0x4df84f40ae0c8229d0d6069e5c8f39a7c299677a09d367fc7b05e3bc380ee652,
                    0xcdc72595f74c7b1043d0e1ffbab734648c838dfb0527d971b602bc216c9619ef,
                    0x0abf5ac974a1ed57f4050aa510dd9c74f508277b39d7973bb2dfccc5eeb0618d,
                    0xb8cd74046ff337f0a7bf2c8e03e10f642c1886798d71806ab1e888d9e5ee87d0,
                    0x838c5655cb21c6cb83313b5a631175dff4963772cce9108188b34ac87c81c41e,
                    0x662ee4dd2dd7b2bc707961b1e646c4047669dcb6584f0d8d770daf5d7e7deb2e,
                    0x388ab20e2573d171a88108e79d820e98f26c0b84aa8b2f4aa4968dbb818ea322,
                    0x93237c50ba75ee485f4c22adf2f741400bdf8d6a9cc7df7ecae576221665d735,
                    0x8448818bb4ae4562849e949e17ac16e0be16688e156b5cf15e098c627c0056a9
                ]
            ),
            (bytes32[32])
        );

        vm.broadcast();
        BPSuckerDelegate(payable(0xd00C4DD2dF16b989DC09666861312A3e78DCfc2F)).claim(
            BPClaim({
                token: JBConstants.NATIVE_TOKEN,
                leaf: BPLeaf({
                    index: 0,
                    beneficiary: msg.sender,
                    projectTokenAmount: 0.01 ether,
                    terminalTokenAmount: 0.01 ether
                }),
                proof: _proofArr
            })
        );
        // BPSuckerDelegate(payable(0xa3cedC2A2bdA2487132273d4eE1107Dad81B6eF9)).executeMessage({
        //     _nonce: 0,
        //     _token: JBConstants.NATIVE_TOKEN,
        //     _terminalTokenAmount: 50_000,
        //     _items: _items
        // });
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
