// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBPayoutTerminal} from "@bananapus/core/src/interfaces/IJBPayoutTerminal.sol";
import {IJBRedeemTerminal} from "@bananapus/core/src/interfaces/IJBRedeemTerminal.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";

import {JBSucker} from "./../JBSucker.sol";
import {IJBSuckerDeployerFeeless} from "../interfaces/IJBSuckerDeployerFeeless.sol";

abstract contract JBAllowanceSucker is JBSucker {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBAllowanceSucker_NoTerminalForToken(uint256 projectId, address token);
    error JBAllowanceSucker_TokenNotAccepted(uint256 projectId, address token);

    //*********************************************************************//
    // ---------------------- internal functions ------------------------- //
    //*********************************************************************//

    /// @notice Redeems the project tokens for the redemption tokens.
    /// @param projectToken the token to redeem.
    /// @param count the amount of project tokens to redeem.
    /// @param token the token to redeem for.
    /// @param minTokensReclaimed the minimum amount of tokens to receive.
    /// @return receivedAmount the amount of tokens received by redeeming.
    function _pullBackingAssets(
        IERC20 projectToken,
        uint256 count,
        address token,
        uint256 minTokensReclaimed
    )
        internal
        virtual
        override
        returns (uint256 receivedAmount)
    {
        // Get the projectToken total supply.
        uint256 totalSupply = projectToken.totalSupply();

        uint256 projectId = PROJECT_ID();

        // Burn the project tokens.
        IJBController(address(DIRECTORY.controllerOf(projectId))).burnTokensOf(
            address(this), projectId, count, string("")
        );

        // Get the primary terminal of the project for the token.
        IJBRedeemTerminal terminal = IJBRedeemTerminal(address(DIRECTORY.primaryTerminalOf(projectId, token)));

        // Make sure a terminal is configured for the token.
        if (address(terminal) == address(0)) {
            revert JBAllowanceSucker_NoTerminalForToken(projectId, token);
        }

        // Get the accounting context for the token.
        JBAccountingContext memory accountingContext = terminal.accountingContextForTokenOf(projectId, token);
        if (accountingContext.currency == 0) {
            revert JBAllowanceSucker_TokenNotAccepted(projectId, token);
        }

        uint256 surplus = terminal.currentSurplusOf(projectId, accountingContext.decimals, accountingContext.currency);

        uint256 backingAssets = mulDiv(count, surplus, totalSupply);

        // Get the balance before we redeem.
        uint256 balanceBefore = _balanceOf(token, address(this));
        receivedAmount = IJBSuckerDeployerFeeless(DEPLOYER).useAllowanceFeeless({
            projectId: projectId,
            terminal: IJBPayoutTerminal(address(terminal)),
            token: token,
            currency: accountingContext.currency,
            amount: backingAssets,
            minTokensReclaimed: minTokensReclaimed
        });

        // Sanity check to make sure we actually received the reported amount.
        // Prevents a malicious terminal from reporting a higher amount than it actually sent.
        // slither-disable-next-line incorrect-equality
        assert(receivedAmount == _balanceOf(token, address(this)) - balanceBefore);
    }
}
