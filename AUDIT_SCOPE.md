# Audit Scope

This is a quick primer on the scope of the Audit of Aragon's ToucanVoting plugin.

> Please note: there might be a few changes in the final design but below should be broadly indicative

## System Overview

![image](https://github.com/aragon/toucan-voting-plugin/assets/45881807/4e6e2543-6b88-4ac8-ad76-b8ba029ffc73)

## Contracts

- Diff indicates that a previously audited contract has been modified and parts of the contract are unchanged.
- New indicates that the contract is new and needs a full audit.

| Contract                      | New/Diff | Info                                                                                  |
| ----------------------------- | -------- | ------------------------------------------------------------------------------------- |
| ToucanVoting                  | Diff     | Changes tokenVoting to allow for splitting voting weight                              |
| GovernanceERC20VotingChain    | Diff     | Timestamp based ERC20Votes with burn functionality                                    |
| MajorityVotingBase            | Diff     | Changes MajorityVoting base contract to facilitate splitting voting weight            |
| IMajorityVoting               | Diff     | Interface changes to faciliate above 2 contract changes                               |
| ToucanVotingSetup             | Diff     | Changes to Aragon OSx setup contract for ToucanVoting (from TokenVoting)              |
| ToucanRelay                   | New      | LayerZero OAppSender to aggreagate Votes on L2 and send to L1 peer                    |
| ToucanReceiver                | New      | LayerZero OAppReceiever to receiver aggregated votes from L1 and vote on ToucanVoting |
| OFTGovernanceAdapter          | New      | Small change to LayerZero's OFTAdapter to add a delegation function                   |
| OFTTokenBridge                | New      | Extends layerZero OFT contract to call mint of underlying token on L2                 |
| ToucanRelaySetup              | New      | Aragon OSx setup contract for ToucanRelay                                             |
| ToucanReceiverSetup           | New      | Aragon OSx setup contract for ToucanReceiver                                          |
| CrossChainExecutor (TBC)      | Diff     | Modifications to Aragon Admin plugin to receive cross chain messages*                 |
| CrossChainExecutorSetup (TBC) | Diff     | Modifications to Aragon OSx setup contract for CrossChainExecutor*                    |

*These are unconfirmed
