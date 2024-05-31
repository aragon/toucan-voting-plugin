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