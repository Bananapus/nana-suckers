// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {BPSuckerDeployerConfig} from "../structs/BPSuckerDeployerConfig.sol";

interface IBPSuckerRegistry {
    error INVALID_DEPLOYER(address deployer);
    error NO_SUCKER_CONFIG();

    event SuckerDeployerAllowed(address deployer);
    event SuckersDeployedFor(uint256 projectId, address[] suckers);

    function isSuckerOf(uint256 projectId, address suckerAddress) external view returns (bool);
    function suckersOf(uint256 projectId) external view returns (address[] memory);
    function suckerDeployerIsAllowed(address deployer) external view returns (bool);

    function allowSuckerDeployer(address deployer) external;
    function deploySuckersFor(uint256 projectId, bytes32 salt, BPSuckerDeployerConfig[] memory configurations)
        external
        returns (address[] memory suckers);
}
