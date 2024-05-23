pragma solidity ^0.8.0;

import {IVoteContainer} from "./IVoteContainer.sol";

interface IToucanRelayMessage {
    struct ToucanVoteMessage {
        uint256 srcChainId;
        uint256 proposalId;
        IVoteContainer.Tally votes;
    }
}
