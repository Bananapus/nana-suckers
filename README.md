# Bananapus Sucker

If someone launches Juicebox projects on multiple chains, they can add suckers to them to allow anyone to burn the project's tokens on one chain (i.e. the local chain), and receive the same amount of tokens on the other chain (i.e. the remote chain). The sucker redeems the tokens on the local chain, and moves the funds it receives to the remote chain.

<details>
  <summary>Table of Contents</summary>
  <ol>
    <li><a href="#usage">Usage</a></li>
  <ul>
    <li><a href="#install">Install</a></li>
    <li><a href="#develop">Develop</a></li>
    <li><a href="#scripts">Scripts</a></li>
    <li><a href="#deployments">Deployments</a></li>
    <ul>
      <li><a href="#with-sphinx">With Sphinx</a></li>
      <li><a href="#without-sphinx">Without Sphinx</a></li>
      </ul>
    <li><a href="#tips">Tips</a></li>
    </ul>
    <li><a href="#repository-layout">Repository Layout</a></li>
    <li><a href="#architecture">Architecture</a></li>
    <li><a href="#description">Description</a></li>
  <ul>
    <li><a href="#basics">Basics</a></li>
    <li><a href="#bridging-tokens">Bridging Tokens</a></li>
    <li><a href="#launching-suckers">Launching Suckers</a></li>
    <li><a href="#using-the-relayer">Using the Relayer</a></li>
    <li><a href="#resources">Resources</a></li>
    </ul>
  </ul>
  </ol>
</details>

_If you're having trouble understanding this contract, take a look at the [core protocol contracts](https://github.com/Bananapus/nana-core) and the [documentation](https://docs.juicebox.money/) first. If you have questions, reach out on [Discord](https://discord.com/invite/ErQYmth4dS)._

## Usage

### Install

How to install `nana-suckers` in another project.

For projects using `npm` to manage dependencies (recommended):

```bash
npm install @bananapus/suckers
```

For projects using `forge` to manage dependencies (not recommended):

```bash
forge install Bananapus/nana-suckers
```

If you're using `forge` to manage dependencies, add `@bananapus/suckers/=lib/nana-suckers/` to `remappings.txt`. You'll also need to install `nana-suckers`' dependencies and add similar remappings for them.

### Develop

`nana-suckers` uses [npm](https://www.npmjs.com/) (version >=20.0.0) for package management and the [Foundry](https://github.com/foundry-rs/foundry) development toolchain for builds, tests, and deployments. To get set up, [install Node.js](https://nodejs.org/en/download) and install [Foundry](https://github.com/foundry-rs/foundry):

```bash
curl -L https://foundry.paradigm.xyz | sh
```

You can download and install dependencies with:

```bash
npm ci && forge install
```

If you run into trouble with `forge install`, try using `git submodule update --init --recursive` to ensure that nested submodules have been properly initialized.

Some useful commands:

| Command               | Description                                         |
| --------------------- | --------------------------------------------------- |
| `forge build`         | Compile the contracts and write artifacts to `out`. |
| `forge fmt`           | Lint.                                               |
| `forge test`          | Run the tests.                                      |
| `forge build --sizes` | Get contract sizes.                                 |
| `forge coverage`      | Generate a test coverage report.                    |
| `foundryup`           | Update foundry. Run this periodically.              |
| `forge clean`         | Remove the build artifacts and cache directories.   |

To learn more, visit the [Foundry Book](https://book.getfoundry.sh/) docs.

### Scripts

For convenience, several utility commands are available in `package.json`.

| Command             | Description                                             |
| ------------------- | ------------------------------------------------------- |
| `npm test`          | Run local tests.                                        |
| `npm run coverage`  | Generate an LCOV test coverage report.                  |
| `npm run artifacts` | Fetch Sphinx artifacts and write them to `deployments/` |

### Deployments

#### With Sphinx

`nana-suckers` manages deployments with [Sphinx](https://www.sphinx.dev). To run the deployment scripts, install the npm `devDependencies` with:

```bash
`npm ci --also=dev`
```

You'll also need to set up a `.env` file based on `.example.env`. Then run one of the following commands:

| Command                   | Description                  |
| ------------------------- | ---------------------------- |
| `npm run deploy:mainnets` | Propose mainnet deployments. |
| `npm run deploy:testnets` | Propose testnet deployments. |

Your teammates can review and approve the proposed deployments in the Sphinx UI. Once approved, the deployments will be executed.

#### Without Sphinx

You can use the Sphinx CLI to run the deployment scripts without paying for Sphinx. First, install the npm `devDependencies` with:

```bash
`npm ci --also=dev`
```

You can deploy the contracts like so:

```bash
PRIVATE_KEY="0x123…" RPC_ETHEREUM_SEPOLIA="https://rpc.ankr.com/eth_sepolia" npx sphinx deploy script/Deploy.s.sol --network ethereum_sepolia
```

This example deploys `nana-suckers` to the Sepolia testnet using the specified private key. You can configure new networks in `foundry.toml`.

### Tips

To view test coverage, run `npm run coverage` to generate an LCOV test report. You can use an extension like [Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters) to view coverage in your editor.

If you're using Nomic Foundation's [Solidity](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity) extension in VSCode, you may run into LSP errors because the extension cannot find dependencies outside of `lib`. You can often fix this by running:

```bash
forge remappings >> remappings.txt
```

This makes the extension aware of default remappings.

## Repository Layout

The root directory contains this README, an MIT license, and config files. The important source directories are:

```
nana-suckers/
├── script/
│   ├── Deploy.s.sol - Deployment script.
│   └── helpers/ - Internal helpers for the deployment script.
├── src/
│   ├── JBArbitrumSucker.sol - Arbitrum-specific JBSucker.
│   ├── JBBaseSucker.sol - Base-specific JBSucker.
│   ├── JBOptimismSucker.sol - Optimism-specific JBSucker.
│   ├── JBSucker.sol - The basic sucker implementation.
│   ├── JBSuckerRegistry.sol - Tracks suckers on each chain.
│   ├── deployers/ - Deployers for each kind of sucker.
│   ├── enums/ - Enums.
│   ├── extensions/
│   │   └── JBAllowanceSucker.sol - An extension which uses overflow allowance instead of redemptions.
│   ├── interfaces/ - Contract interfaces.
│   ├── libraries/ - Libraries.
│   ├── structs/ - Structs.
│   └── utils/
│       └── MerkleLib.sol - The incremental merkle tree implementation suckers use to store claims.
└── test/
    ├── Fork.t.sol - Fork tests.
    ├── mocks/ - Mock contracts for testing.
    └── unit/
        ├── merkle.t.sol - Merkle tree unit tests.
        └── registry.t.sol - A registry unit test.
```

Other directories:

```
nana-suckers/
├── .github/
│   └── workflows/ - CI/CD workflows.
└── deployments/ - Sphinx deployment logs.
```

## Architecture

On each network (Ethereum, Arbitrum, Optimism, and Base):

```mermaid
graph TD;
    A[JBSuckerRegistry] -->|exposes| B["deploySuckersFor(…)"]
    B -->|calls| C[IJBSuckerDeployer]
    C -->|deploys| D[JBSucker]
    A -->|tracks| D
```

For an example project deployed on mainnet and Optimism with a `JBOptimismSucker` on each network:

```mermaid
graph TD;
    subgraph Mainnet
    A[Project] -->|redeemed funds| B[JBOptimismSucker]
    B -->|burns/mints tokens| A
    end
    subgraph Optimism
    C[Project] -->|redeemed funds| D[JBOptimismSucker]
    D -->|burns/mints tokens| C
    end
    B <-->|merkle roots/funds| D
```

## Description

_This description is adapted from [Bridging in Juicebox v4](https://filip.world/post/suckers/)._

Juicebox v4 introduces the [`JBSucker`](https://github.com/bananapus/nana-suckers) contracts for bridging project tokens and funds (terminal tokens) across EVM chains. Here's what you'll need to know if you're building a frontend or service which interacts with them.

### Basics

`JBSucker` contracts are deployed in pairs, with one on each network being bridged to or from – for now, suckers bridge between Ethereum mainnet and a specific L2. The [`JBSucker`](https://github.com/Bananapus/nana-suckers/blob/master/src/JBSucker.sol) contract implements core logic, and is extended by network-specific implementations adapted to each L2's bridging solution:

| Sucker                                                                                               | Networks                      | Description                                                                                                                                                                                                                                |
| ---------------------------------------------------------------------------------------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`JBOptimismSucker`](https://github.com/Bananapus/nana-suckers/blob/master/src/JBOptimismSucker.sol) | Ethereum Mainnet and Optimism | Uses the [OP Standard Bridge](https://docs.optimism.io/builders/app-developers/bridging/standard-bridge) and the [OP Messenger](https://docs.optimism.io/builders/app-developers/bridging/messaging)                                       |
| [`JBBaseSucker`](https://github.com/Bananapus/nana-suckers/blob/master/src/JBBaseSucker.sol)         | Ethereum Mainnet and Base     | A thin wrapper around `JBOptimismSucker`                                                                                                                                                                                                   |
| [`JBArbitrumSucker`](https://github.com/Bananapus/nana-suckers/blob/master/src/JBArbitrumSucker.sol) | Ethereum Mainnet and Arbitrum | Uses the [Arbitrum Inbox](https://docs.arbitrum.io/build-decentralized-apps/cross-chain-messaging) and the [Arbitrum Gateway](https://docs.arbitrum.io/build-decentralized-apps/token-bridging/bridge-tokens-programmatically/get-started) |

Suckers use two [merkle trees](https://en.wikipedia.org/wiki/Merkle_tree) to track project token claims associated with each terminal token it supports:

- The _outbox tree_ tracks tokens on the local chain – the network that the sucker is on.
- The _inbox tree_ tracks tokens which have been bridged from the peer chain – the network that the sucker's peer is on.

For example, a sucker which supports bridging ETH and USDC would have four trees – an inbox and outbox tree for each token. These trees are append-only, and when they're bridged over to the other chain, they aren't deleted – they only update the remote inbox tree with the latest root.

To insert project tokens into the outbox tree, users call `JBSucker.prepare(…)` with:

1. The amount of project tokens to bridge, and
2. the terminal token to bridge with them.

The sucker redeems those project tokens to reclaim the chosen terminal token from the project's primary terminal for it. Then the sucker inserts a claim with this information into the outbox tree.

Anyone can bridge an outbox tree to the peer chain by calling `JBSucker.toRemote(…)`. The outbox tree then _becomes_ the peer sucker's inbox tree for that token. Users can claim their tokens on the peer chain by providing a merkle proof which shows that their claim is in the inbox tree.

### Bridging Tokens

Imagine that the "OhioDAO" project is deployed on Ethereum mainnet and Optimism:

- It has the $OHIO ERC-20 project token and a `JBOptimismSucker` deployed on each network.
- Its suckers map\* mainnet ETH to Optimism ETH, and vice versa.

\* Each sucker has mappings from terminal tokens on the local chain to associated terminal tokens on the remote chain.

_Here's how Jimmy can bridge his $OHIO tokens (and the corresponding ETH) from mainnet to Optimism._

First, Jimmy pays OhioDAO 1 ETH on Ethereum mainnet by calling [`JBMultiTerminal.pay(…)`](https://github.com/Bananapus/nana-core/blob/main/src/JBMultiTerminal.sol#L273):

```solidity
JBMultiTerminal.pay{value: 1 ether}({
    projectId: 12,
    token: 0x000000000000000000000000000000000000EEEe,
    amount: 1 ether,
    beneficiary: 0x1234…,
    minReturnedTokens: 0,
    memo: "OhioDAO rules",
    metadata: 0x
});
```

- `projectId` 12 is OhioDAO's project ID.
- The (terminal) `token` is ETH, represented by [`JBConstants.NATIVE_TOKEN`](https://github.com/Bananapus/nana-core/blob/main/src/libraries/JBConstants.sol)
- The `beneficiary` `0x1234…` is Jimmy's address.

OhioDAO's ruleset has a `weight` of `1e18`, so Jimmy receives 1 $OHIO in return (`1e18` $OHIO). Before he can bridge his $OHIO to Optimism, Jimmy has to call the $OHIO contract's `ERC20.approve(…)` function to allow the `JBOptimismSucker` to use his balance:

```solidity
JBERC20.approve({
    spender: 0x5678…,
    value: 1e18
});
```

The `spender` `0x5678…` is the `JBOptimismSucker`'s Ethereum mainnet address, and the `value` is Jimmy's $OHIO balance. Jimmy can now prepare his $OHIO for bridging by calling `JBOptimismSucker.prepare(…)`:

```solidity
JBOptimismSucker.prepare({
    projectTokenAmount: 1e18,
    beneficiary: 0x1234…,
    minTokensReclaimed: 0,
    token: 0x000000000000000000000000000000000000EEEe
});
```

Once this is called, the sucker:

- Transfers Jimmy's $OHIO to itself.
- Redeems the $OHIO using OhioDAO's primary ETH terminal.
- Adds a claim with this information to its ETH outbox tree.

Specifically, the `prepare(…)` function inserts a leaf into the ETH outbox tree – the leaf is a keccak256 hash of the beneficiary's address, the amount of $OHIO which was redeemed, and the amount of ETH reclaimed by that redemption.

To bridge the outbox tree over, Jimmy (or someone else) calls `JBOptimismSucker.toRemote(…)`, which takes one argument – the terminal token whose outbox tree should be bridged. Jimmy wants to bridge the ETH outbox tree, so he passes in `0x000000000000000000000000000000000000EEEe`. After a few minutes, the sucker will have bridged over the outbox tree and the ETH it got by redeeming Jimmy's $OHIO, which calls the peer sucker's `JBOptimismSucker.fromRemote(…)` function. The Optimism OhioDAO sucker's ETH inbox tree is updated with the new merkle root which contains Jimmy's claim.

Jimmy can claim his $OHIO on Optimism by calling `JBOptimismSucker.claim(…)`, which takes a single [`JBClaim`](https://github.com/Bananapus/nana-suckers/blob/master/src/structs/JBClaim.sol) as its argument. `JBClaim` looks like this:

```solidity
struct JBClaim {
    address token;
    JBLeaf leaf;
    // Must be `JBSucker.TREE_DEPTH` long.
    bytes32[32] proof;
}
```

Here's the [`JBLeaf`](https://github.com/Bananapus/nana-suckers/blob/master/src/structs/JBLeaf.sol) struct:

```solidity
/// @notice A leaf in the inbox or outbox tree of a `JBSucker`. Used to `claim` tokens from the inbox tree.
struct JBLeaf {
    uint256 index;
    address beneficiary;
    uint256 projectTokenAmount;
    uint256 terminalTokenAmount;
}
```

These claims can be difficult for integrators to put together – they would have to track every insertion and build merkle proofs for each one. To make this easier, I wrote the [`juicerkle`](https://github.com/Bananapus/juicerkle) service which returns all of the available claims for a specific beneficiary. To use it, `POST` a json request to `/claims`:

| Field         | JS Type  | Description                                                               |
| ------------- | -------- | ------------------------------------------------------------------------- |
| `chainId`     | `int`    | The network ID for the sucker contract being claimed from.                |
| `sucker`      | `string` | The address of the sucker being claimed from.                             |
| `token`       | `string` | The address of the terminal token whose inbox tree is being claimed from. |
| `beneficiary` | `string` | The address of the beneficiary we're getting the available claims for.    |

Jimmy's claims request looks like this:

```js
{
    "chainId": 10,
    "sucker": "0x5678…",
    "token": "0x000000000000000000000000000000000000EEEe",
    "beneficiary": "0x1234…" // jimmy.eth
}
```

The `chainId` is Optimism's network ID. Jimmy's getting his claims for the ETH inbox tree of the `JBOptimismSucker` at `0x5678…`. The `juicerkle` service will look through the entire inbox tree and return all of Jimmy's available claims as `JBClaim` structs. The response looks like this:

```js
[
  {
    Token: "0x000000000000000000000000000000000000eeee",
    Leaf: {
      Index: 0,
      Beneficiary: "0x1234…", // jimmy.eth
      ProjectTokenAmount: 1000000000000000000, // 1e18
      TerminalTokenAmount: 1000000000000000000, // 1e18
    },
    Proof: [
      [
        229, 206, 51, 48, 16, 242, 169, 29, 47, 33, 39, 105, 34, 55, 172, 232,
        217, 243, 168, 149, 38, 202, 133, 68, 191, 119, 165, 97, 59, 232, 212,
        14,
      ],
      [
        33, 40, 178, 36, 156, 7, 175, 252, 47, 196, 238, 239, 170, 52, 239, 153,
        66, 111, 173, 24, 113, 164, 25, 185, 54, 47, 170, 32, 232, 56, 97, 254,
      ],
      // More 32-byte chunks…
    ],
  },
  // More claims…
];
```

Jimmy calls `JBOptimismSucker.claim(…)` with this to claim his $OHIO on Optimism. If the sucker's `ADD_TO_BALANCE_MODE` is set to `ON_CLAIM`, the bridged ETH associated with Jimmy's $OHIO is immediately added to OhioDAO's balance. Otherwise, it will be added once someone calls `JBOptimismSucker.addOutstandingAmountToBalance(…)`.

### Launching Suckers

There are a few requirements for launching a sucker pair:

1. Projects must already be deployed on both chains. The project IDs don't have to match.
2. Both projects must have a 100% redemption rate for the suckers to redeem project tokens for terminal tokens. That is, [`JBRulesetMetadata.redemptionRate`](https://github.com/Bananapus/nana-core/blob/main/src/structs/JBRulesetMetadata.sol) must be `10_000`, which is [`JBConstants.MAX_REDEMPTION_RATE`](https://github.com/Bananapus/nana-core/blob/main/src/libraries/JBConstants.sol).
3. Both projects must allow owner minting for the suckers to mint bridged project tokens. That is, [`JBRulesetMetadata.allowOwnerMinting`](https://github.com/Bananapus/nana-core/blob/main/src/structs/JBRulesetMetadata.sol) must be `true`.
4. Both projects must have an ERC-20 project token. If one doesn't, launch it with [`JBController.deployERC20For(…)`](https://github.com/Bananapus/nana-core/blob/main/src/JBController.sol#L620).

Suckers are deployed through the [`JBSuckerRegistry`](https://github.com/Bananapus/nana-suckers/blob/master/src/JBSuckerRegistry.sol) on each chain. In the process of deploying the suckers, the sucker registry maps local tokens to remote tokens, so we'll have to give it permission:

```solidity
JBPermissionsData memory mapTokenPermission = JBPermissionsData({
    operator: 0x9ABC…,
    projectId: 12,
    permissionIds: [28], // JBPermissionIds.MAP_SUCKER_TOKEN == 28
});

JBPermissions.setPermissionsFor({
    account: 0x1234…,
    permissionsData: mapTokenPermission
});
```

In this example, the project owner `0x1234…` gives the `JBSuckerRegistry` at `0x9ABC…` permission to map tokens for project 12's suckers. Now the owner can deploy the suckers:

```solidity
JBTokenMapping memory ethMapping = JBTokenMapping({
    localToken: 0x000000000000000000000000000000000000EEEe,
    minGas: 100_000, // 100k gas minimum
    remoteToken: 0x000000000000000000000000000000000000EEEe,
    minBridgeAmount: 25e15, // 0.025 ETH
});

JBSuckerDeployerConfig memory config = JBSuckerDeployerConfig({
    deployer: 0xcdef…,
    mappings: [ethMapping]
});

JBSuckerRegistry.deploySuckersFor({
    projectId: 12,
    salt: 0xfce167d38e3d9c2a0375c172d979c39c696f2450616565c1c3284e00f0fac074,
    configurations: [config]
});
```

- The [`JBTokenMapping`](https://github.com/Bananapus/nana-suckers/blob/master/src/structs/JBTokenMapping.sol) maps local mainnet ETH to remote Optimism ETH.
  - To prevent spam, the mapping has a `minBridgeAmount` – ours blocks attempts to bridge less than 0.025 ETH.
  - To prevent transactions from failing, our `minGas` requires a gas limit greater than 100,000 wei.
  - These are good starting values, but you may need to adjust them – if your token has expensive transfer logic, you may need a higher `minGas`.
- The [`JBSuckerDeployerConfig`](https://github.com/Bananapus/nana-suckers/blob/master/src/structs/JBSuckerDeployerConfig.sol) uses the [`JBOptimismSuckerDeployer`](https://github.com/Bananapus/nana-suckers/blob/master/src/deployers/JBOptimismSuckerDeployer.sol) at `0xcdef…` to deploy the sucker.
  - You can only use approved sucker deployers through the registry. Check for `SuckerDeployerAllowed` events or contact the registry's owner to figure out which deployers are approved.
- We call `JBSuckerRegistry.deploySuckersFor(…)` with the project's ID (12), a randomly generated 32-byte salt, and the configuration.
  - **For the suckers to be peers, the `salt` has to match on both chains and the same address must call `deploySuckersFor(…)`.**

The suckers are deployed! We have to give the sucker permission to mint bridged project tokens:

```solidity
JBPermissionsData memory mintPermission = JBPermissionsData({
    operator: 0x1357…,
    projectId: 12,
    permissionIds: [9], // JBPermissionIds.MINT_TOKENS == 9
});

JBPermissions.setPermissionsFor({
    account: 0x1234…,
    permissionsData: mintPermission
});
```

In this example, the project owner `0x1234…` gives their new `JBSucker` at `0x1357…` permission to mint project 12's tokens.

Repeat this process on the other chain to deploy the peer sucker, and the project should be ready for bridging.

### Using the Relayer

_This tech is still under construction – expect this to change._

Bridging from L1 to L2 is straightforward. Bridging from L2 to L1 usually requires an extra step to finalize the withdrawal, which is different for each L2. For OP Stack networks like Optimism or Base, this is the [withdrawal flow](https://docs.optimism.io/stack/protocol/withdrawal-flow):

> 1.  The **withdrawal initiating transaction**, which the user submits on L2.
> 2.  The **withdrawal proving transaction**, which the user submits on L1 to prove that the withdrawal is legitimate (based on a merkle patricia trie root that commits to the state of the L2ToL1MessagePasser's storage on L2)
> 3.  The **withdrawal finalizing transaction**, which the user submits on L1 after the fault challenge period has passed, to actually run the transaction on L1.

Users can do this manually, but it's a hassle. To simplify this process, 0xBA5ED wrote the [`bananapus-sucker-relayer`](https://github.com/Bananapus/bananapus-sucker-relayer), a tool which automatically proves and finalizes withdrawals from Optimism or Base to Ethereum mainnet. It listens for withdrawals and automatically completes the withdrawal process using [OpenZeppelin Defender](https://www.openzeppelin.com/defender).

To use the relayer, project creators have to create an OpenZeppelin Defender account, set up a relayer through their dashboard, and fund it with ETH (to pay gas fees). This relayer is still in development, so expect changes.

### Resources

1. The `nana-suckers` contracts use Nomad's [`MerkleLib`](https://github.com/nomad-xyz/nomad-monorepo/blob/main/solidity/nomad-core/libs/Merkle.sol) merkle tree implementation, which is based on the eth2 deposit contract. I couldn't find a comparable implementation in Golang, so I wrote one which you're welcome to use: the [`tree`](https://github.com/Bananapus/juicerkle/blob/master/tree/tree.go) package in the [`juicerkle`](https://github.com/Bananapus/juicerkle) project. It provides utilities for calculating roots, as well as building and verifying merkle proofs. I use this implementation in the `juicerkle` service to generate claims.
2. To thoroughly test `juicerkle` in practice, I built the end-to-end [`juicerkle-tester`](https://github.com/Bananapus/juicerkle-tester). As well as testing the `juicerkle` service, it serves as a useful bridging process walkthrough – it deploys appropriately configured projects, tokens, and suckers, and bridges between them.

### Managing suckers

Once configured suckers should manage themselves, however its important to stay up-to-date on changes to the bridge infrastructure that is used by the sucker of your choice. 
In the case that a change is made that would cause suckers to no longer be functional/compatible with the underlying bridge infrastructure there are two options:
(note, make sure to perform these actions on BOTH sides of the suckers)

#### Disable a token
In the case that a change to the underlying bridge causes only a single (or few) tokens to no longer function you might want to disable just those tokens. Your first step should be to call `mapToken(...)` with the token you wish to disable and `remoteToken` set to `address(0)` to disable it.
If this does not work because the bridge will not let you perform a final transfer with the remaining funds then you can activate the `EmergencyHatch` for the tokens that are giving issues. 

Enabling the `EmergencyHatch` allows tokens to be withdrawn by their depositors on the chain where they were deposited. Only those whose funds have not been moved to the remote chain can withdraw using the `EmergencyHatch`.
An important side-note is that once an EmergencyHatch is opened for a token, the token will never be able to be bridged using this sucker. You can however deploy a new sucker for that token.

#### Deprecate the suckers
In the case that the bridiging infrastructure will no longer work you should deprecate the sucker, this will make it so that the sucker will start its shutdown procedure. Depending on the sucker implementation this will have a minimum duration which is needed to ensure that no funds/roots get lost while in transit. After this duration all tokens will allow for exit through the `EmergencyHatch` and no new messages will be accepted.

This makes it so that even if at some point in the future the bridge starts sending fake/malicious transfers the sucker will reject all of these.

When deprecating suckers make sure that your bridge infrastructure does not have pending messages that can/should be retried. Once the deprecation is complete these messages will no longer be accepted by the sucker.
