pragma solidity ^0.8.20;

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanRelayUpgradeable} from "@voting-chain/crosschain/ToucanRelayUpgradeable.sol";
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
        Tally memory _tally,
        Voter[] memory _votes
    ) public {
        proposals[_proposalId].tally = _tally;
        for (uint256 i = 0; i < _votes.length; i++) {
            address voter = _votes[i].voter;
            Tally memory vote = _votes[i].vote;
            proposals[_proposalId].voters[voter] = vote;
        }
    }

    function setProposalState(uint256 _proposalId, Tally memory _tally) public {
        proposals[_proposalId].tally = _tally;
    }
}

contract MockToucanRelayUpgradeable is ToucanRelayUpgradeable {
    constructor() {}

    struct Voter {
        address voter;
        Tally vote;
    }

    function setProposalState(
        uint256 _proposalId,
        Tally memory _tally,
        Voter[] memory _votes
    ) public {
        proposals[_proposalId].tally = _tally;
        for (uint256 i = 0; i < _votes.length; i++) {
            address voter = _votes[i].voter;
            Tally memory vote = _votes[i].vote;
            proposals[_proposalId].voters[voter] = vote;
        }
    }

    function setProposalState(uint256 _proposalId, Tally memory _tally) public {
        proposals[_proposalId].tally = _tally;
    }
}
