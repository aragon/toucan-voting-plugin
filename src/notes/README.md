# The new setup contract

Our setup must define:

1. PrepareInstallation  : for *new* builds
2. PrepareUpdate        : for *existing* builds
3. PrepareUninstallation: for both


## What does a *new* build need:

- ToucanVoting deployed from a UUPS Proxy
- Initialize with DAO, token and some voting settings
    - Toucan voting defaults to requiring VoteReplacement
        - This could be added to the relayer
    - We could add a "configure for crosschain" flag which would require VoteReplacement

- Grant permissions:
    - MINT
    - EXECUTE
    - UPDATE_SETTINGS

This is the basics, we then should consider about the helper functions:

- We can probably keep most of these for now
- The main thing is to skip the interface checks if people want to


## What does an *existing* build need

- It cannot have an active proposal
    - Fetch proposalCount
    - Check the latestProposal
        - If it's:
            - not started 
            - in progress
        - The user must wait
- We may want to configure to VoteReplacement but I think this can be done in the relay


## Uninstallation

- No changes as it's just the permissions



# The receiver setup contract

- If we want to setup the receiver as a plugin

- Deploy the receiver
- Pass the DAO, Plugin, Governance token
    - Check the governance token but allow a skip
    - Whitelist the plugin on the setup contract
- Set the permissions to update the REFUND collector and RECEIVER ADMIN as the DAO
- Deploy the OFTAdapter as a helper?
    - Why?
    - This could be a separate function really