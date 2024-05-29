pragma solidity ^0.8.20;

import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

contract MockToucanRelay is ToucanRelay {
    constructor(
        address _token,
        address _lzEndpoint,
        address _dao
    ) ToucanRelay(_token, _lzEndpoint, _dao) {}

    struct Voter {
        address voter;
        Tally vote;
    }

    function setProposalState(
        uint256 _proposalId,
        uint256 _executionChainId,
        Tally memory _tally,
        Voter[] memory _votes
    ) public {
        proposals[_executionChainId][_proposalId].tally = _tally;
        for (uint256 i = 0; i < _votes.length; i++) {
            address voter = _votes[i].voter;
            Tally memory vote = _votes[i].vote;
            proposals[_executionChainId][_proposalId].voters[voter] = vote;
        }
    }

    function setProposalState(
        uint256 _proposalId,
        uint256 _executionChainId,
        Tally memory _tally
    ) public {
        proposals[_executionChainId][_proposalId].tally = _tally;
    }
}
