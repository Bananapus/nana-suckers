// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Global constants used across Juicebox contracts.
library ARBAddresses {
    /// @notice The respective Inbox used by L1 or Testnet L1
    address public constant L1_ETH_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address public constant L1_SEP_INBOX = 0xaAe29B0366299461418F5324a79Afc425BE5ae21;

    /// @notice The gateway router used to bridge tokens between the local and remote chain.
    address public constant L1_GATEWAY_ROUTER = 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    address public constant L2_GATEWAY_ROUTER = 0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;

    /// @notice The testnet gateway routers used for bridging tokens.
    address public constant L1_SEP_GATEWAY_ROUTER = 0xcE18836b233C83325Cc8848CA4487e94C6288264;
    address public constant L2_SEP_GATEWAY_ROUTER = 0x9fDD1C4E4AA24EEc1d913FABea925594a20d43C7;
}
