// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {JBLayer} from "../enums/JBLayer.sol";
import {IArbGatewayRouter} from "../interfaces/IArbGatewayRouter.sol";
import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

interface IJBArbitrumSuckerDeployer {
    function layer() external view returns (JBLayer);
    function inbox() external view returns (IInbox);
    function gatewayRouter() external view returns (IArbGatewayRouter);
}
