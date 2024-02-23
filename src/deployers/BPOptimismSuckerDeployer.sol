// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../BPOptimismSucker.sol";
import {IBPSucker} from "./../interfaces/IBPSucker.sol";
import {IBPSuckerDeployerFeeless} from "./../interfaces/IBPSuckerDeployerFeeless.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {JBPermissioned, IJBPermissions} from "@bananapus/core/src/abstract/JBPermissioned.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/terminal/IJBPayoutTerminal.sol";

contract BPOptimismSuckerDeployer is JBPermissioned, IBPSuckerDeployerFeeless {
    error ONLY_SUCKERS();

    IJBPrices immutable PRICES;
    IJBRulesets immutable RULESETS;
    OPMessenger immutable MESSENGER;
    OPStandardBridge immutable BRIDGE;
    IJBDirectory immutable DIRECTORY;
    IJBTokens immutable TOKENS;

    /// @notice A mapping of suckers deployed by this contract.
    mapping(address => bool) public isSucker;

    constructor(
        IJBPrices _prices,
        IJBRulesets _rulesets,
        OPMessenger _messenger,
        OPStandardBridge _bridge,
        IJBDirectory _directory,
        IJBTokens _tokens,
        IJBPermissions _permissions
    ) JBPermissioned(_permissions) {
        PRICES = _prices;
        RULESETS = _rulesets;
        MESSENGER = _messenger;
        BRIDGE = _bridge;
        DIRECTORY = _directory;
        TOKENS = _tokens;
    }

    /// @notice Create a new sucker for a specific project.
    /// @dev uses the sender address as the salt, requires the same sender to deploy on both chains.
    /// @param _localProjectId the project id on this chain.
    /// @param _salt the salt to use for the create2 address.
    /// @return _sucker the address of the new sucker.
    function createForSender(uint256 _localProjectId, bytes32 _salt) external returns (IBPSucker _sucker) {
        _salt = keccak256(abi.encodePacked(msg.sender, _salt));
        _sucker = IBPSucker(
            address(
                new BPOptimismSucker{salt: _salt}(
                    PRICES, RULESETS, MESSENGER, BRIDGE, DIRECTORY, TOKENS, PERMISSIONS, address(0), _localProjectId
                )
            )
        );
        isSucker[address(_sucker)] = true;
    }

    /// @notice Use the allowance of a project witgout paying exit fees.
    /// @dev This function can only be called by suckers deployed by this contract, and only if the project owner has given the specicifc sucker permission to use the allowance.
    /// @dev This is not necesarily feeless, as it still requires JBDAO to mark this as feeless first.
    /// @param _projectId the project id.
    /// @param _terminal the terminal to use.
    /// @param _token the token to use the allowance of.
    /// @param _currency the currency the amount is denominated in.
    /// @param _amount the amount to get from the terminal, denomated in the currency.
    /// @param _minReceivedTokens the minimum amount of tokens to receive.
    /// @return the amount of tokens received.
    function useAllowanceFeeless(
        uint256 _projectId,
        IJBPayoutTerminal _terminal,
        address _token,
        uint32 _currency,
        uint256 _amount,
        uint256 _minReceivedTokens
    ) external returns (uint256) {
        // Make sure the caller is a sucker.
        if (!isSucker[msg.sender]) {
            revert ONLY_SUCKERS();
        }

        // Access control: Only allowed suckes can use the allowance.
        _requirePermissionFrom(DIRECTORY.PROJECTS().ownerOf(_projectId), _projectId, JBPermissionIds.USE_ALLOWANCE);

        // Use the allowance.
        return _terminal.useAllowanceOf(
            _projectId, _token, _amount, _currency, _minReceivedTokens, payable(address(msg.sender)), string("")
        );
    }
}
