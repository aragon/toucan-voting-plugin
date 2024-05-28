// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IVoteContainer} from "./IVoteContainer.sol";

interface IToucanRelayMessage {
    struct ToucanVoteMessage {
        uint256 votingChainId;
        uint256 proposalId;
        IVoteContainer.Tally votes;
    }
}
