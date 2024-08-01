// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./../JBSucker.sol";

import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBSuckerDeployerFeeless} from "../interfaces/IJBSuckerDeployerFeeless.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";

abstract contract JBAllowanceSucker is JBSucker {
    /// @notice Redeems the project tokens for the redemption tokens.
    /// @param _projectToken the token to redeem.
    /// @param _amount the amount of project tokens to redeem.
    /// @param _token the token to redeem for.
    /// @param _minReceivedTokens the minimum amount of tokens to receive.
    /// @return _receivedAmount the amount of tokens received by redeeming.
    function _getBackingAssets(IERC20 _projectToken, uint256 _amount, address _token, uint256 _minReceivedTokens)
        internal
        virtual
        override
        returns (uint256 _receivedAmount)
    {
        // Get the projectToken total supply.
        uint256 _totalSupply = _projectToken.totalSupply();

        // Burn the project tokens.
        IJBController(address(DIRECTORY.controllerOf(PROJECT_ID))).burnTokensOf(
            address(this), PROJECT_ID, _amount, string("")
        );

        // Get the primary terminal of the project for the token.
        IJBRedeemTerminal _terminal = IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(PROJECT_ID, _token)));

        // Make sure a terminal is configured for the token.
        if (address(_terminal) == address(0)) {
            revert TOKEN_NOT_MAPPED(_token);
        }

        // Get the accounting context for the token.
        JBAccountingContext memory _accountingContext = _terminal.accountingContextForTokenOf(PROJECT_ID, _token);
        if (_accountingContext.decimals == 0 && _accountingContext.currency == 0) {
            revert TOKEN_NOT_MAPPED(_token);
        }

        uint256 _surplus =
            _terminal.currentSurplusOf(PROJECT_ID, _accountingContext.decimals, _accountingContext.currency);

        // TODO: replace with PRB-Math muldiv.
        uint256 _backingAssets = _amount * _surplus / _totalSupply;

        // Get the balance before we redeem.
        uint256 _balanceBefore = _balanceOf(_token, address(this));
        _receivedAmount = IJBSuckerDeployerFeeless(DEPLOYER).useAllowanceFeeless(
            PROJECT_ID,
            IJBPayoutTerminal(address(_terminal)),
            _token,
            _accountingContext.currency,
            _backingAssets,
            _minReceivedTokens
        );

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        // slither-disable-next-line incorrect-equality
        assert(_receivedAmount == _balanceOf(_token, address(this)) - _balanceBefore);
    }
}
