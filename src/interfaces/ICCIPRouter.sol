// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IWrappedNativeToken} from "./IWrappedNativeToken.sol";

// https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/applications/EtherSenderReceiver.sol

interface ICCIPRouter is IRouterClient {
    function getWrappedNative() external view returns (IWrappedNativeToken);
}
