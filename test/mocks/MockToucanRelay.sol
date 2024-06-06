pragma solidity ^0.8.20;

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanRelayUpgradeable} from "@voting-chain/crosschain/ToucanRelayUpgradeable.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

contract MockToucanRelay is ToucanRelayUpgradeable {
    constructor() {}

    uint private chainId_;

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

    function setChainId(uint id) public {
        chainId_ = id;
    }

    function _chainId() internal view override returns (uint) {
        if (chainId_ == 0) {
            return block.chainid;
        } else {
            return chainId_;
        }
    }
}
