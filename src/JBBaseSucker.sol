// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBOptimismSucker.sol";

contract JBBaseSucker is JBOptimismSucker {
    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory A contract storing directories of terminals and controllers for each project.
    /// @param permissions A contract storing permissions.
    /// @param tokens A contract that manages token minting and burning.
    /// @param addToBalanceMode The mode of adding tokens to balance.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        JBAddToBalanceMode addToBalanceMode
    )
        JBOptimismSucker(directory, permissions, tokens, addToBalanceMode)
    {}

    //*********************************************************************//
    // ------------------------ external views --------------------------- //
    //*********************************************************************//

    /// @notice Returns the chain on which the peer is located.
    /// @return chainId of the peer.
    function peerChainId() external view virtual override returns (uint256) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return 8453;
        if (chainId == 8453) return 1;
        if (chainId == 11_155_111) return 84_532;
        if (chainId == 84_532) return 11_155_111;
        return 0;
    }
}
