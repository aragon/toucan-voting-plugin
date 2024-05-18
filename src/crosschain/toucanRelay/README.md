# Toucan Relay

The relay contract is a crosschain plugin that facilitates inter-chain voting. There are a few main responsibilities:

1. Forwarding proposal data:

The relay on the execution chain must send an encoded proposal ID to the voting chain(s)*

* Do we need to send the data across? Anyone can create data against a deterministic proposal id, so why send it in the first place?
- If you fuck up the timestamp, that could be extremely problematic
- But that's a separate issue: you can easily get the full proposal ID from another chain. 

2. Aggregating voting data on the voting chain:

The relay on the voting chain allows users to vote and change vote against a proposal ID. The proposal ID is simply an encoding of enough proposal data to make it unique and run validations on the voting chain. 

- If we do this, we probably need to add a check to ensure multiple proposals have not been created with the same ID, and revert the Tx if you try and do that.
- Easy as:

```ts
Proposal memory proposal = proposals[_newProposalId];

if (proposal.parameters.snapshotBlock != 0) {
    revert ProposalIdAlreadyExists();
}
```
3. Send votes to the execution chain

The relayer should allow, permissionlessly, anyone to send the current vote aggregate to the execution chain. This will relay the current aggregated votes across


4. Receive aggregated votes from each chain.

The relay contract should be aware of all votes coming in from each chain. Assuming it trust its counterparties on the voting chain, it can then change its aggregate of aggregates.


5. Ping the contract holding the locked tokens to update its vote on the execution proposal

This requires that the locked contract has a mechanism for allowing the locked votes to be updated. This can also be permissionless.



# A race condition

There is always a race condition with immediate execution, namely:

- At time T: the vote ends, the proposal can be executed.
- At time T-1: users on all chains can still vote
- Assuming the bridging transaction takes >1 second, there exists a window where a user can vote, but the data will not have reached the execution chain.
- Therefore, we probably should: have a grace period enabled where:
    - New votes cannot be cast
    - Existing votes can be changed

- This doesn't really affect the issue tbh. You still have the period up until the grace period. 