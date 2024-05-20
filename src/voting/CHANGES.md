# Token -> Toucan changes

Line by line changes for Toucan Voting


## MajorityVotingBase

- Add a `VotingMode`: `PartialWithReplacement` allows partial voting with replacement
    - Side note: it's super weird that the voting mode is setup as an enum instead of allowing combinations of settings
    - Maybe we can improve this as it's tough to work with for combinations of voting settings

### Updating the Proposal Struct
- We need to store the vote history as a 3 word tally. This is a net 40k gas increase for each voter in the worst case (but no increase in the base case)
- the `Proposal` struct needs extremely careful updating:
```js
struct Proposal {
    bool executed;
    ProposalParameters parameters;
    Tally tally;
    /// @dev - storage slot here might need to point to a new struct with the first word as a _deprecated slot
    mapping(address => IMajorityVoting.VoteOption) voters;
    IDAO.Action[] actions;
    uint256 allowFailureMap;
}
```

So we would have:

```js
struct Proposal {
    bool executed;
    ProposalParameters parameters;
    Tally tally;
    mapping(address => VoteHistory) voters;
    IDAO.Action[] actions;
    uint256 allowFailureMap;
}
struct VoteHistory {
    // this represents the old VoteOption but if we want multiple votes per user 
    // we need to store an actual tally
    uint256 _deprecated;
    Tally votes;
}
```
I think the above is fine, because the mapping points to a new location in memory

We could equally do:

```js
struct Proposal {
    bool executed;
    ProposalParameters parameters;
    Tally tally;
    // @dev old vote history when only one option was allowed. Was a mapping of address => vote history
    bytes32 _deprecated;
    IDAO.Action[] actions;
    uint256 allowFailureMap;
    mapping(address voter => Tally votes) voters
}
```

Which I think also works because each proposal is stored against the id:

```js
mapping(uint256 => Proposal) internal proposals;
```
Need to check but I think option 2 is better

## TokenVoting

- deprecate oz counters in favour of the encoded proposal ids 
- the _createProposal will need adjusting 
- adjust natspec for `isMember` as only refers to current chain
- the `_vote` function needs changing:
    - we need to remove the state and instead fetch the tally
    - we need to ensure the new tally is valid given the voting power
    - we do the standard updating of voting settings*

*we need to update these in a lot of places...is it fully necessary?
- On the source chain, we keep a track of userVotes => chainVotes
- On the dst chain, we keep a track of chainVotes => aggregateVotesAcrossAllchains
- On the plugin we keep a track of aggregateVotesAcrossAllchains + otherVotes => aggregateVotes
- So, unfortunately, yes, on the L1:
    - <=3 storage slots per chain
    - <=3 storage slots to update the chain total
    - <=3 storage slots to update the user (all cross chain voters) on the plugin
    - <=3 storage slots to update the global total

So if you split your vote on the L2, you have to pay for 6 slots, and the DAO has to pay for 6 (120k gas in the worst case)

- _canVote needs the new method allowed and the replacement setting looked at. 

## Setup

TBC
