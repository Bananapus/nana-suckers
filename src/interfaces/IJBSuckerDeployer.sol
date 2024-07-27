// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSucker} from "./IJBSucker.sol";

interface IJBSuckerDeployer {
    function createForSender(uint256 localProjectId, bytes32 salt) external returns (IJBSucker sucker);

    function TEMP_PROJECT_ID() external view returns (uint256);
}
