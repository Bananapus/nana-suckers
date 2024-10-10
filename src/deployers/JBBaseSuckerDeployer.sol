// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./JBOptimismSuckerDeployer.sol";

// Exact same as JBOptimismSuckerDeployer, we do this so we get a seperate artifact for Base.
contract JBBaseSuckerDeployer is JBOptimismSuckerDeployer {
    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param directory The directory of terminals and controllers for projects.
    /// @param permissions The permissions contract for the deployer.
    /// @param tokens The contract that manages token minting and burning.
    /// @param configurator The address of the configurator.
    constructor(
        IJBDirectory directory,
        IJBPermissions permissions,
        IJBTokens tokens,
        address configurator
    )
        JBOptimismSuckerDeployer(directory, permissions, tokens, configurator)
    {}
}
