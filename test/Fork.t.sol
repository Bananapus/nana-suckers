// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "@openzeppelin/contracts/utils/Strings.sol";
// import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// import {MockPriceFeed} from "@bananapus/core/test/mock/MockPriceFeed.sol";

// import {BPOptimismSucker, IJBDirectory, IJBTokens, IJBToken, IERC20, BPTokenMapping, OPMessenger} from "../src/BPOptimismSucker.sol";
// import "@bananapus/core/src/interfaces/IJBController.sol";
// import "@bananapus/core/src/interfaces/terminal/IJBRedeemTerminal.sol";
// import "@bananapus/core/src/interfaces/terminal/IJBMultiTerminal.sol";
// import "@bananapus/core/src/interfaces/IJBPriceFeed.sol";
// import "@bananapus/core/src/libraries/JBConstants.sol";
// import "@bananapus/permission-ids/src/JBPermissionIds.sol";
// import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
// import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
// import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
// import {IJBPermissions, JBPermissionsData} from "@bananapus/core/src/interfaces/IJBPermissions.sol";

// import {MockMessenger} from "./mocks/MockMessenger.sol";

// contract BPOptimismSuckerTest is Test {
//     BPOptimismSuckerHarnass public suckerL1;
//     BPOptimismSuckerHarnass public suckerL2;

//     IJBController CONTROLLER;
//     IJBDirectory DIRECTORY;
//     IJBTokens TOKENS;
//     IJBPermissions PERMISSIONS;
//     IJBRedeemTerminal MULTI_TERMINAL;

//     struct TestBridgeItems {
//         address sender;
//         address beneficiary;
//         uint256 projectTokenAmount;
//     }

//     string DEPLOYMENT_JSON = "@bananapus/core/broadcast/Deploy.s.sol/11155111/run-latest.json";

//     MockMessenger _mockMessenger;

//     function setUp() public {
//         vm.createSelectFork("https://ethereum-sepolia.publicnode.com"); // Will start on latest block by default

//         CONTROLLER = IJBController(_getDeploymentAddress(DEPLOYMENT_JSON, "JBController"));
//         DIRECTORY = IJBDirectory(_getDeploymentAddress(DEPLOYMENT_JSON, "JBDirectory"));
//         TOKENS = IJBTokens(_getDeploymentAddress(DEPLOYMENT_JSON, "JBTokens"));
//         PERMISSIONS = IJBPermissions(_getDeploymentAddress(DEPLOYMENT_JSON, "JBPermissions"));
//         MULTI_TERMINAL = IJBRedeemTerminal(_getDeploymentAddress(DEPLOYMENT_JSON, "JBMultiTerminal"));

//         // Configure a mock manager that mocks the OP bridge
//         _mockMessenger = new MockMessenger();
//     }

//     function test_linkProjects() public {
//         address _L1ProjectOwner = makeAddr("L1ProjectOwner");
//         address _L2ProjectOwner = makeAddr("L2ProjectOwner");

//         _configureAndLinkProjects(_L1ProjectOwner, _L2ProjectOwner);

//         assertEq(address(suckerL1.PEER()), address(suckerL2));
//         assertEq(address(suckerL2.PEER()), address(suckerL1));
//     }

//     function test_suck_native(uint256 _payAmount) public {
//         _payAmount = _bound(_payAmount, 0.1 ether, 100_000 ether);

//         // Configure the projects and suckers
//         (uint256 _L1Project, uint256 _L2Project) = _configureAndLinkProjects(makeAddr("L1ProjectOwner"), makeAddr("L2ProjectOwner"));

//         // Fund the user
//         address _user = makeAddr("user");
//         vm.deal(_user, _payAmount);

//         // User pays project and receives tokens in exchange on L2
//         vm.startPrank(_user);
//         uint256 _receivedTokens = MULTI_TERMINAL.pay{value: _payAmount}(
//             _L2Project, JBConstants.NATIVE_TOKEN, _payAmount, address(_user), 0, "", bytes("")
//         );

//         // The items to bridge.
//         TestBridgeItems[] memory _items = new TestBridgeItems[](1);
//         _items[0] = TestBridgeItems({
//             sender: _user,
//             beneficiary: _user,
//             projectTokenAmount: _receivedTokens
//         });

//         // Expect the L1 terminal to receive the funds
//         vm.expectCall(
//             address(MULTI_TERMINAL),
//             abi.encodeCall(
//                 IJBTerminal.addToBalanceOf,
//                 (_L1Project, JBConstants.NATIVE_TOKEN, _payAmount, false, string(""), bytes(""))
//             )
//         );

//         // Handle all the bridging.
//         _bridge(_items, JBConstants.NATIVE_TOKEN, _L2Project, suckerL2);

//         IERC20 _l1Token = IERC20(address(TOKENS.tokenOf(_L1Project)));
//         IERC20 _l2Token = IERC20(address(TOKENS.tokenOf(_L2Project)));

//         for(uint256 _i; _i < _items.length; _i++){
//             // Beneficiary should now have the tokens on L1
//             assertEq(_l1Token.balanceOf(_items[_i].beneficiary), _receivedTokens);
//             // Sender should no longer have any tokens on L2
//             assertEq(_l2Token.balanceOf(_items[_i].sender), 0);
//         }
//     }

//     function test_suck_token(uint256 _payAmount) public {
//         _payAmount = _bound(_payAmount, 0.1 ether, 100_000 ether);

//         // Configure the projects and suckers
//         address _projectOwnerL1 = makeAddr("L1ProjectOwner");
//         address _projectOwnerL2 = makeAddr("L2ProjectOwner");
//         (uint256 _L1Project, uint256 _L2Project) = _configureAndLinkProjects(_projectOwnerL1, _projectOwnerL2);

//         // Some random DAI token I found on the blockexplorer
//         ERC20Mock _L2ERC20Token = new ERC20Mock();

//         // Configure the L2 terminal for the token.
//         {
//             address[] memory _tokens = new address[](1);
//             _tokens[0] = address(_L2ERC20Token);

//             vm.startPrank(_projectOwnerL2);
//             MULTI_TERMINAL.addAccountingContextsFor(_L2Project, _tokens);

//             // Add the price feed for it.
//             IJBMultiTerminal(address(MULTI_TERMINAL)).STORE().PRICES().addPriceFeedFor(
//                 _L2Project,
//                 uint32(uint160(JBConstants.NATIVE_TOKEN)),
//                 uint32(uint160(address(_L2ERC20Token))),
//                 IJBPriceFeed(address(new MockPriceFeed(1 ether, 18)))
//             );

//             vm.stopPrank();
//         }

//         ERC20Mock _L1ERC20Token = new ERC20Mock();
//         {
//             address[] memory _tokens = new address[](1);
//             _tokens[0] = address(_L1ERC20Token);

//             // Configure the L1 to accept the token.
//             vm.startPrank(_projectOwnerL1);
//             MULTI_TERMINAL.addAccountingContextsFor(_L1Project, _tokens);

//             // Add the price feed for it.
//             IJBMultiTerminal(address(MULTI_TERMINAL)).STORE().PRICES().addPriceFeedFor(
//                 _L1Project,
//                 uint32(uint160(JBConstants.NATIVE_TOKEN)),
//                 uint32(uint160(address(_L1ERC20Token))),
//                 IJBPriceFeed(address(new MockPriceFeed(1 ether, 18)))
//             );

//             vm.stopPrank();
//         }

//         // Configure the mock bridge for the token.
//         _mockMessenger.setRemoteToken(address(_L2ERC20Token), address(_L1ERC20Token));

//         // // Configure the L2 sucker for the token.
//         // vm.prank(_projectOwnerL2);
//         // suckerL2.mapToken(address(_L2ERC20Token), BPTokenMapping({
//         //     minGas: 200_000,
//         //     remoteToken: address(_L1ERC20Token)
//         // }));

//         // Fund the user
//         address _user = makeAddr("user");
//         _L2ERC20Token.mint(_user, _payAmount);

//         TestBridgeItems[] memory _items = new TestBridgeItems[](1);

//         // User pays project and receives tokens in exchange on L2
//         vm.startPrank(_user);
//         _L2ERC20Token.approve(address(MULTI_TERMINAL), _payAmount);
//         uint256 _receivedTokens = MULTI_TERMINAL.pay(
//             _L2Project, address(_L2ERC20Token), _payAmount, address(_user), 0, "", bytes("")
//         );
//         vm.stopPrank();

//         // The items to bridge.
//         _items[0] = TestBridgeItems({
//             sender: _user,
//             beneficiary: _user,
//             projectTokenAmount: _receivedTokens
//         });

//          // Expect the L1 terminal to receive the funds.
//         vm.expectCall(
//             address(MULTI_TERMINAL),
//             abi.encodeCall(
//                 IJBTerminal.addToBalanceOf,
//                 (_L1Project, address(_L1ERC20Token), _payAmount, false, string(""), bytes(""))
//             )
//         );

//         // Handle all the bridging.
//         _bridge(_items, address(_L2ERC20Token), _L2Project, suckerL2);

//         IERC20 _l1Token = IERC20(address(TOKENS.tokenOf(_L1Project)));
//         IERC20 _l2Token = IERC20(address(TOKENS.tokenOf(_L2Project)));
//         for(uint256 _i; _i < _items.length; _i++){
//             // Beneficiary should now have the tokens on L1
//             assertEq(_l1Token.balanceOf(_items[_i].beneficiary), _receivedTokens);
//             // Sender should no longer have any tokens on L2
//             assertEq(_l2Token.balanceOf(_items[_i].sender), 0);
//         }
//     }

//     function _bridge(
//         TestBridgeItems[] memory _items,
//         address _terminalToken,
//         uint256 _project,
//         BPOptimismSuckerHarnass _sucker
//     ) internal {
//          IERC20 _projectToken = IERC20(address(TOKENS.tokenOf(_project)));

//          // Tracks the beneficiaries.
//          address[] memory _beneficiaries = new address[](_items.length);
//          uint256 _totalProjectTokenAmount;

//          // Give approval to spend tokens and add to the bridge queue.
//          for(uint256 _i; _i < _items.length; ++_i){
//             vm.startPrank(_items[_i].sender);
//             _projectToken.approve(address(_sucker), _items[_i].projectTokenAmount);

//             // Add our item to the queue.
//             _sucker.bridge(
//                 _items[_i].projectTokenAmount,
//                 _items[_i].beneficiary,
//                 0,
//                 _terminalToken
//             );

//             // Add to the list of beneficiaries for the next step.
//             _beneficiaries[_i] = _items[_i].beneficiary;
//             _totalProjectTokenAmount += _items[_i].projectTokenAmount;
//             vm.stopPrank();
//          }

//         //  // Execute our queue item.
//         // _sucker.toRemote(
//         //     _terminalToken,
//         //     _beneficiaries
//         // );

//         // Get the remote sucker.
//         // BPOptimismSuckerHarnass _remoteSucker = BPOptimismSuckerHarnass(payable(address(_sucker.PEER())));

//         // address _remoteTerminalToken;
//         // if(_terminalToken != JBConstants.NATIVE_TOKEN) {
//         //     (,_remoteTerminalToken) = _sucker.token(_terminalToken);
//         // } else {
//         //     _remoteTerminalToken = JBConstants.NATIVE_TOKEN;
//         // }

//         // // On the remote chain we execute the message.
//         // _remoteSucker.executeMessage(
//         //     _sucker.ForTest_GetNonce() - 1,
//         //     _remoteTerminalToken,
//         //     _totalProjectTokenAmount,
//         //     _sucker.ForTest_GetBridgeItems()
//         // );

//     }

//     function _configureAndLinkProjects(address _L1ProjectOwner, address _L2ProjectOwner)
//         internal
//         returns (uint256 _L1Project, uint256 _L2Project)
//     {
//         // Deploy two projects
//         _L1Project = _deployJBProject(_L1ProjectOwner, "Bananapus", "NANA");
//         _L2Project = _deployJBProject(_L2ProjectOwner, "BananapusOptimism", "OPNANA");

//         // Get the determenistic addresses for the suckers
//         uint256 _nonce = vm.getNonce(address(this));
//         address _suckerL1 = vm.computeCreateAddress(address(this), _nonce);
//         address _suckerL2 = vm.computeCreateAddress(address(this), _nonce + 1);

//         // Deploy the pair of suckers
//         suckerL1 = new BPOptimismSuckerHarnass(_mockMessenger, DIRECTORY, TOKENS, PERMISSIONS, _suckerL2, _L1Project);
//         suckerL2 = new BPOptimismSuckerHarnass(_mockMessenger, DIRECTORY, TOKENS, PERMISSIONS, _suckerL1, _L2Project);

//         uint256[] memory _permissions = new uint256[](1);
//         _permissions[0] = JBPermissionIds.MINT_TOKENS;

//         // Grant 'MINT_TOKENS' permission to the JBSuckers of their localChains
//         vm.prank(_L1ProjectOwner);
//         PERMISSIONS.setPermissionsFor(
//             address(_L1ProjectOwner),
//             JBPermissionsData({operator: address(suckerL1), projectId: _L1Project, permissionIds: _permissions})
//         );

//         vm.prank(_L2ProjectOwner);
//         PERMISSIONS.setPermissionsFor(
//             address(_L2ProjectOwner),
//             JBPermissionsData({operator: address(suckerL2), projectId: _L2Project, permissionIds: _permissions})
//         );
//     }

//     function _deployJBProject(address _owner, string memory _tokenName, string memory _tokenSymbol)
//         internal
//         returns (uint256 _projectId)
//     {
//         // IJBTerminal[] memory _terminals = new IJBTerminal[](1);
//         // _terminals[0] = IJBTerminal(address(MULTI_TERMINAL));

//         JBRulesetMetadata memory _metadata = JBRulesetMetadata({
//             reservedRate: 0,
//             redemptionRate: JBConstants.MAX_REDEMPTION_RATE,
//             baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
//             pausePay: false,
//             pauseCreditTransfers: false,
//             allowOwnerMinting: true,
//             allowTerminalMigration: false,
//             allowSetTerminals: false,
//             allowControllerMigration: false,
//             allowSetController: false,
//             holdFees: false,
//             useTotalSurplusForRedemptions: false,
//             useDataHookForPay: false,
//             useDataHookForRedeem: false,
//             dataHook: address(0),
//             metadata: 0
//         });

//         // Package up ruleset configuration.
//         JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
//         _rulesetConfig[0].mustStartAtOrAfter = 0;
//         _rulesetConfig[0].duration = 0;
//         _rulesetConfig[0].weight = 10 ** 18;
//         _rulesetConfig[0].metadata = _metadata;
//         _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
//         _rulesetConfig[0].fundAccessLimitGroups = new JBFundAccessLimitGroup[](0);

//         // Package up terminal configuration.
//         JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
//         address[] memory _tokens = new address[](1);
//         _tokens[0] = JBConstants.NATIVE_TOKEN;
//         _terminalConfigurations[0] = JBTerminalConfig({terminal: MULTI_TERMINAL, tokensToAccept: _tokens});

//         _projectId = CONTROLLER.launchProjectFor({
//             owner: _owner,
//             projectMetadata: "myIPFSHash",
//             rulesetConfigurations: _rulesetConfig,
//             terminalConfigurations: _terminalConfigurations,
//             memo: ""
//         });

//         vm.prank(_owner);
//         CONTROLLER.deployERC20For(_projectId, _tokenName, _tokenSymbol);
//     }

//     /**
//      * @notice Get the address of a contract that was deployed by the Deploy script.
//      *     @dev Reverts if the contract was not found.
//      *     @param _path The path to the deployment file.
//      *     @param _contractName The name of the contract to get the address of.
//      *     @return The address of the contract.
//      */
//     function _getDeploymentAddress(string memory _path, string memory _contractName) internal view returns (address) {
//         string memory _deploymentJson = vm.readFile(_path);
//         uint256 _nOfTransactions = stdJson.readStringArray(_deploymentJson, ".transactions").length;

//         for (uint256 i = 0; i < _nOfTransactions; i++) {
//             string memory _currentKey = string.concat(".transactions", "[", Strings.toString(i), "]");
//             string memory _currentContractName =
//                 stdJson.readString(_deploymentJson, string.concat(_currentKey, ".contractName"));

//             if (keccak256(abi.encodePacked(_currentContractName)) == keccak256(abi.encodePacked(_contractName))) {
//                 return stdJson.readAddress(_deploymentJson, string.concat(_currentKey, ".contractAddress"));
//             }
//         }

//         revert(
//             string.concat("Could not find contract with name '", _contractName, "' in deployment file '", _path, "'")
//         );
//     }
// }

// contract BPOptimismSuckerHarnass is BPOptimismSucker {

//     // BPSuckBridgeItem[] internal _latestBridgeItems;

//     constructor(
//         OPMessenger _messenger,
//         IJBDirectory _directory,
//         IJBTokens _tokens,
//         IJBPermissions _permissions,
//         address _peer,
//         uint256 _projectId
//     ) BPOptimismSucker(
//         _messenger,
//         address(0)
//         _directory,
//         _tokens,
//         _permissions,
//         _peer,
//         _projectId
//     ) {}

//     // function ForTest_GetNonce() external view returns(uint256) {
//     //     return nonce;
//     // }

//     // function ForTest_GetBridgeItems() external returns (BPSuckBridgeItem[] memory) {
//     //     return _latestBridgeItems;
//     // }

//     // //  function _sendItemsOverBridge(
//     //     address _token,
//     //     uint256 _tokenAmount,
//     //     BPSuckBridgeItem[] memory _itemsToBridge
//     // ) internal virtual override returns (bytes32 _messageHash) {
//     //     delete _latestBridgeItems;
//     //     for(uint256 _i; _i < _itemsToBridge.length; _i++){
//     //         _latestBridgeItems.push(_itemsToBridge[_i]);
//     //     }
//     //     // super._sendItemsOverBridge(_token, _tokenAmount, _itemsToBridge);
//     // }
// }
