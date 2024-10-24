// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IOPStandardBridge} from "./IOPStandardBridge.sol";
import {IOPMessenger} from "./IOPMessenger.sol";

interface IJBOpSuckerDeployer {
    function opBridge() external view returns (IOPStandardBridge);
    function opMessenger() external view returns (IOPMessenger);
    function setChainSpecificConstants(IOPMessenger messenger, IOPStandardBridge bridge) external;
}
