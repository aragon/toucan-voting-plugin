# ToucanVoting

![toucan-voting](https://github.com/aragon/toucan-voting-plugin/assets/45881807/6f6d9187-753b-4397-ae33-75c55c238157)

<!-- Add demo link or video here -->

## Introduction

We envision a world where governance is both accessible to all, and natively multichain. Where users need not tradeoff between economic security, and meaningful participation onchain. ToucanVoting lets your voters fly free - voting for low or no-cost across multiple chains, while still maintaining complete, trustless control of the entire system. 

Specifically, ToucanVoting is a cross-chain governance system for DAOs in the Ethereum Ecosystem built on [Aragon OSx](https://aragon.org/aragonosx). It leverages the capabilities of LayerZero v2 to facilitate low-cost and trustless governance of DAOs across multiple chains.

# Table of Contents

- [Introduction](#introduction)
- [Features and Benefits](#features-and-benefits)
- [Installing on your DAO](#installing-on-your-dao)
- [Building Locally](#building-locally)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Deep dive](#deep-dive)
  - [Key Terms](#key-terms)
  - [Overview](#overview)
  - [Permissions](#permissions)
  - [Layer Zero Peers](#layer-zero-peers)
  - [Proposal ID vs Proposal Ref](#proposal-id-vs-proposal-ref)
- [Workflows](#workflows)
  - [Stages in crosschain voting](#stages-in-crosschain-voting)
  - [Crosschain Governance](#crosschain-governance)
- [Restrictions and Limitations](#restrictions-and-limitations)


## Features and Benefits

### Flexible

Any ERC20 or ERC20Votes token can be made omnichain, allowing governance across multiple chains and enabling tokens to be bridged to any chain supported by the broker. Any number of chains can be used in governance, with over 70 currently supported.

### Low Cost

Voters can move to chains with extremely low fees while governing mainnet DAOs. The only requirement is users bridge their tokens to the desired chain. 

Votes are aggregated before relaying back to the main chain, allowing for thousands of votes to be compressed to a single transaction posted back to the main chain.

### Modular

Built on [Aragon OSx](https://aragon.org/aragonosx), Toucan is simply another plugin for your DAO. It can be combined with other governance primitives, upgraded, extended or removed as your governance needs change.

### Trustless

All Components across all chains remain fully controlled by the original DAO via the battle-tested Aragon permissions system, ensuring trustless and decentralized governance.

## Installing on your DAO

A fully automated deployment is in the works! In the meantime please contact the Aragon team on our [discord](https://discord.gg/aragonorg) and we will get you setup with crosschain voting.

## Building Locally

To set up the ToucanVoting project, you will need [Foundry](https://getfoundry.sh). Additionally, ensure you have `lcov` and `genhtml` installed for coverage reporting. If you have `make` installed, you can use commands in the [Makefile](./Makefile)

### Prerequisites

- **Foundry**: Follow the installation instructions at [Foundry](https://getfoundry.sh).
- **Make**: Ensure you have `make` installed. Most Unix-like systems come with `make` pre-installed. On Debian-based systems, you can install it using `apt`:
  ```sh
  sudo apt install build-essential
  ```
- **lcov**: Install `lcov` using your package manager. On Debian-based systems:
  ```sh
  sudo apt install lcov
  ```
- **genhtml**: This is typically included with `lcov`. Ensure it is available in your system.

### Installation

To set up the repository, follow these steps:

Initialize the repository and run the test suite with coverage report generated in [report/](./report/index.html).

```sh
make install
```

You can also manually do this:

```sh
forge install # install deps
forge build   # compile contracts
forge test    # run the test suite
```

> Note: Due to issues with LayerZero's test helpers, it's not possible to run `forge coverage` directly, please use `make coverage-report` instead.

## Deep dive

The following is a technical deep dive into the ToucanVoting architecture. It is designed for developers seeking to have a full understanding of the system.

### Key Terms

- DAO: The Aragon OSx DAO that governs all other components on that particular chain. By 'governs' we mean it has full control over all permissions for that chain, and has full control.

- Action: An onchain transaction that will be executed by the DAO. This could be, for example, to send tokens to a contract, to install a new governance plugin, or to enable a new voting chain.

- Proposal: proposals contain actions. Token holders vote on proposals and, if they pass, the actions will be executed by the DAO.

- GovernanceERC20: an ERC20 token that implements the IVotes interface. It allows for voting with delegation.

- Delegation: A user allows another ethereum address to vote on their behalf. In the context of toucan voting, all tokens bridged to other voting chains delegate their voting power to the bridging contracts, so that their votes can be relayed back to the execution chain.

- Execution Chain: the primary chain on which the DAO operates. Proposals are created on this chain. There is only one execution chain in the system.

- Voting Chain: secondary chain(s) supported by the main DAO. A sub-DAO will be deployed on each of these chains, and proposals can execute cross-chain transactions from the execution chain to make changes on the voting chain(s). There can be many voting chains.

- Proposal ID: a numerical ID for an execution chain proposal. Typically is a counter starting at 0 and incrementing by 1 for each new proposal. Used on execution chains.

- Proposal Reference: Used on voting chains and in the ToucanReceiver. It is a 256 bit encoding of some basic proposal data which allows users to vote against proposals on voting chains _without_ said proposal needing to be bridged. See the [Proposal Reference](#proposal-id-vs-proposal-ref) section for details.

### Overview

### Permissions

This repo uses [Aragon OSx 1.3.0 contracts](https://github.com/aragon/osx/tree/v1.3.0) and solidity 0.8.17.

> You can see examples of these in the [execution chain setup test](./test/unit/execution-chain/setup/ExecutionChainSetup.t.sol) and [voting chain setup test](./test/unit/voting-chain/setup/VotingChainSetup.t.sol)

#### Execution Chain

| Component                | Permission Granted    | Target Component         | Chain           |
| ------------------------ | --------------------- | ------------------------ | --------------- |
| DAO.sol                  | EXECUTE_PERMISSION    | ToucanVoting.sol         | Execution Chain |
| DAO.sol                  | OAPP_ADMINISTRATOR    | ToucanReceiver.sol       | Execution Chain |
| DAO.sol                  | OAPP_ADMINISTRATOR    | GovernanceOFTAdapter.sol | Execution Chain |
| DAO.sol                  | OAPP_ADMINISTRATOR    | ActionRelay.sol          | Execution Chain |
| DAO.sol                  | XCHAIN_ACTION_RELAYER | ActionRelay.sol          | Execution Chain |
| DAO.sol                  | MINT_PERMISSION       | GovernanceERC20.sol      | Execution Chain |
| GovernanceOFTAdapter.sol | Delegates to          | ToucanReceiver           | Execution Chain |

#### Voting Chain

| Component      | Permission Granted | Target Component               | Chain        |
| -------------- | ------------------ | ------------------------------ | ------------ |
| DAO.sol        | OAPP_ADMINISTRATOR | AdminXChain                    | Voting Chain |
| DAO.sol        | OAPP_ADMINISTRATOR | OFTTokenBridge                 | Voting Chain |
| DAO.sol        | OAPP_ADMINISTRATOR | ToucanRelay                    | Voting Chain |
| OFTTokenBridge | MINT_PERMISSION    | GovernanceERC20VotingChain.sol | Voting Chain |
| OFTTokenBridge | BURN_PERMISSION    | GovernanceERC20VotingChain.sol | Voting Chain |

> Note that, as part of installation, an [Aragon Admin plugin](https://github.com/aragon/admin-plugin/) is configured during setup and later removed.

### Layer Zero Peers

OApps require a peer to be set by the `OAPP_ADMINISTRATOR` (The DAO), calling `setPeer`. If the peers are not set, crosschain messages will not be accepted. The peers are as follows:

| Component                | Peer Component           |
| ------------------------ | ------------------------ |
| ToucanVoting.sol         | ToucanReceiver.sol       |
| ToucanReceiver.sol       | ToucanVoting.sol         |
| GovernanceOFTAdapter.sol | OFTTokenBridge.sol       |
| OFTTokenBridge.sol       | GovernanceOFTAdapter.sol |
| ActionRelay.sol          | AdminXChain.sol          |
| AdminXChain.sol          | ActionRelay.sol          |

### Proposal ID vs Proposal Ref

In ToucanVoting.sol, `ProposalId` are auto-incrementing counters that increase with each new proposal created on the execution chain. We explicitly designed the voting plugin to be completely agnostic of cross-chain operations, so that the DAO is free to replace it with other governance plugins and not worry about cross chain.

Additionaly, we wanted to avoid having DAOs bridge propsosals to all voting chains: this takes time, incurs gas fees and opens up other difficulties involved in bridging.

The solution is the `ProposalReference`: a unique identifier for proposals on chains other than the execution chain.

This `ProposalReference` allows users to vote on without requiring the bridging of proposals. The [`ProposalRefEncoder`](./src//libs//ProposalRefEncoder.sol) library provides a solution by encoding salient information about a proposal into a single 256-bit value.

#### Encoding Scheme

A proposal reference is composed of the following fields:

- Proposal ID (32 bits): Unique identifier for the proposal.
- Plugin Address (128 bits): First 128 bits of the plugin address on the execution chain.
- Start Timestamp (32 bits): Timestamp when the proposal voting starts.
- End Timestamp (32 bits): Timestamp when the proposal voting ends.
- Block Snapshot Timestamp (32 bits): Timestamp to check voting power at.

#### Usage

> For more details, refer to the [ProposalRefEncoder.sol](link-to-your-code).

| Component      | Identifier Type                                         |
| -------------- | ------------------------------------------------------- |
| ToucanRelay    | Proposal References                                     |
| ToucanReceiver | Proposal References (stores votes against Proposal IDs) |
| ToucanVoting   | Proposal IDs                                            |
| DAO            | Proposal IDs                                            |

## Workflows

A high level workflow can be seen below for a single voting chain. Click the image for an interactive viewer.

[![image](https://github.com/aragon/toucan-voting-plugin/assets/45881807/cdd74771-3ac3-4abf-8ed6-5db4c76457ea)](https://link.excalidraw.com/readonly/C0HefSwZ1NJXTpXzuT5q)

### Stages in crosschain voting

- **Bridge Tokens**:

  - Users must bridge from the execution chain to the voting chain _prior_ to proposal creation using `GovernanceOFTAdapter.sol`. This locks tokens in `GovAdapter` and sends a mint transaction on the voting chain (`OFTTokenBridge.sol` calls mint on `GovernanceERC20VotingChain.sol`).
  - Users can bridge back by burning tokens on the voting chain, this will unlock the tokens on the `GovernanceOFTAdapter.sol`.

- **Create Proposal**:

  - A holder of a sufficient quantity (set by DAO) of governance tokens creates a proposal on `ToucanVoting.sol`.

- **Voting Phase**:

  - When `block.timestamp` > `startTimestamp` of the proposal, users who had voting power when the proposal was created can vote.
  - Users can vote directly on the execution chain:
    - Fetch a proposal reference from `ToucanReceiver.sol` on the execution chain.
    - Vote on `ToucanRelay.sol` using the proposal reference.
    - Votes are aggregated until dispatched.

- **Dispatch Votes**:

  - Anyone can call `dispatchVotes` on `ToucanRelay`, which sends the votes to `ToucanReceiver.sol`.

- **Receive Votes**:

  - `ToucanReceiver.sol:lzReceive` is called, which looks up the proposal ID and validates the proposal reference. If it's valid, it updates its vote on the `ToucanVoting.sol` plugin with the newly received votes.

- **Execute Proposal**:
  - After the proposal finishes, execute the proposal on `ToucanVoting.sol`, which calls `dao.execute`.

#### Crosschain Governance

- **Manage Other Chains**:

  - Optionally, if the DAO needs to manage another chain, encode an action into the proposal for the DAO to call the `ActionRelay.sol` contract.
  - `ActionRelay.sol` takes the action(s) and sends them to `AdminXChain.sol`, which has EXECUTE permission on the voting chain DAO.

- **Admin Control**:

  - The voting chain DAO is the admin over all components on the voting chain, so it can execute any required actions.

> This workflow ensures that the main DAO on the execution chain remains in control of the entire system, even when voting and actions are distributed across multiple chains.

## Restrictions and Limitations

### Limitations

1. **Single Execution Chain Support**:

   - Only one execution chain is supported for creating and executing proposals.
   - **Caveat**: The DAO can change the execution chain at a later date, but this version of cross-chain voting will no longer function if that happens.

2. **Bridging Tokens from Multiple Chains**:

   - If a user already has tokens on multiple chains, they will need to bridge them back to the execution chain and then bridge via the canonical chain. This ensures all tokens are correctly registered for governance.

3. **Proposal Creation Limitation**:

   - Currently, the only action supported for token holders on the voting chains is voting, not proposal creation. Users on voting chains must bridge to the execution chain to create proposals.
   - This is something we plan to address in the future.

4. **Token Wrapping Requirements**:

   - On the execution chain, if you have an ERC20 token, it must be wrapped to add governance functionality.
   - If you have a voting token, it must be an ERC20Votes token, or it will be wrapped to a compatible voting token.

5. **Delegation Not Preserved**:

   - Delegation on the execution chain is not preserved on the voting chain. Users will need to re-delegate after bridging.
   - Preserving delegation history is a feature we are considering in future updates.

6. **Manual Bridging Required**:

   - Users must manually bridge their tokens from the execution chain. Automating this process could be a feature in the future.

7. **Dispatching Votes**:

   - Someone must call `dispatchVotes` for aggregate votes to be relayed back to the execution chain. This will incur a bridging fee, which is expected to be paid by the DAO.
   - If nobody pays for it before the vote closes, votes will not be counted.
   - Automating this process could be a feature in the future.

8. **Gas Limit for Bridging Actions**:
   - Bridging actions cross-chain requires passing the gas limit in the proposal. The proposal creator should ensure enough gas has been passed to cover execution. Failing to do so can result in proposals being unable to execute.
   - In the future, additional fallback utilities will be provided, but currently, operators should calculate the required gas. The DAO can claim refunded gas back on the voting chain using the sweep function.
