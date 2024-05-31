# Token -> Toucan changes

Line by line changes for Toucan Voting


## MajorityVotingBase

- If we are, globally, adding the feature of partial voting, then potentially we don't need a new  vote setting:
- In `Standard` Mode: you can partially vote, but you can't change your vote later
    - Maybe better that you vote once, with full voting power
- In `EarlyExecution` Mode: 
    - Same as standard
- In `VoteReplacement`:
    - Change your vote

The question is, should we allow for partial votes in `VoteReplacement`?
- For now, sure, maybe we restrict it later


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

The setup contract for TokenVoting does the following:
- Stores the bytecode of the governance tokens and the tokenVoting plugin
- Checks to see if you've brought your own token
- Deploys or wraps your token
- Deploys the plugin
- Creates the permissions the plugin will need
- Returns the helpers and permissions

## Update



# Builds versus releases

TokenVoting inherits from MajorityVoting which is UUPSUpgradeable. This means we can create a build and preserve the storage. The main challenges as I see it that `VotingMode` is incompatible with split voting.

What we therefore need to adhere to the build rules. 

- We can *add* external functions and storage variables but we cannot *change* or *remove* them.

On `vote`:

```js
    function vote(
        uint256 _proposalId,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) public;

// add an overload

    function vote(
        uint256 _proposalId,
        Tally _voteOptions,
        bool _tryEarlyExecution
    ) public;
```
Internally, vote needs to write to the tally storage variable

On `getVoteOption`:

This is tricky. I'd be tempted to leave it as-is and update the storage variable to point to deprecated. We can update the natspec to say this shouldn't be used but can be checked for historical votes.


Then we can add `getVoteOptions` which will return the tally

We also need to deprecate the VoteCast event and create VotesCast as a new event

On `_canVote`, it's an internal function so we can change it


On `createProposal`:

This, annoyingly, has a voting option. I think we just keep as is and set it to "deprecated" and add an overload that doesn't have any vote data. We can opt to revert the use of createProposal in this way or, alternatively, just add an overload to vote with the tally. 


TODO: natspec, iface


## Security risk-reentrancy:

- `votingToken.getVotes` has the potential for read-only reentrancy. Need to be careful about mitigations. 

# MajorityVotingBase && IMajorityVoting

- Moved Tally into the interface so we can reference in the overloaded functions

- Overloaded `VoteCast` event with `voteOptions` tally
- Added deprecation warning on `VoteCast`

> Qu: should we still emit in the single vote case? This will keep UIs working if they choose not to add the new voting method

- Overloaded:
    - vote
    - canVote
    - VoteCast (e)
    - createProposal
- Added `getVoteOptions` 


- changed `Proposal.voters` to `Proposal._deprecated`
- added `Proposal.lastVotes`


- Added overloaded `createProposal` virtual function
- Linked overloaded `canVote` to overloaded `_canVote`
- Linked overloaded 

- Created `_convertVoteOptionToTally` which fetches voting power of the sender as 

- Modified `supportsInterface` to use the hash of the `createProposal` string signature seing as the selector is no longer unique.
    - Another option is to use a differently named function


- Added new Error:
    - VoteMultipleForbidden

# Token Voting

- Added internal `_createProposal` function 
- Added implementation of `createProposal` overload