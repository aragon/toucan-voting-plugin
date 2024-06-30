// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

contract MockToucanReceiver is ToucanReceiver {
    constructor() {}

    struct VotesByChain {
        uint chainId;
        Tally votes;
    }

    function setState(
        uint _proposalId,
        Tally memory aggregateVotes,
        VotesByChain[] memory _votesByChain
    ) public {
        _votes[votingPlugin][_proposalId].aggregateVotes = aggregateVotes;
        for (uint i = 0; i < _votesByChain.length; i++) {
            _votes[votingPlugin][_proposalId].votesByChain[
                _votesByChain[i].chainId
            ] = _votesByChain[i].votes;
        }
    }

    function setAggregateVotes(uint _proposalId, Tally memory _aggregateVotes) public {
        _votes[votingPlugin][_proposalId].aggregateVotes = _aggregateVotes;
    }

    function receiveVotes(uint _votingChainId, uint _proposalId, Tally memory _votes) public {
        _receiveVotes(_votingChainId, _proposalId, _votes);
    }

    function _lzReceive(bytes calldata message, Origin calldata o, bytes calldata d) external {
        bytes32 g;
        address e;
        _lzReceive(o, g, message, e, d);
    }
}

// This contract is used when we need to bypass canReceiveVotes checks
contract MockToucanReceiverCanReceivePass is MockToucanReceiver {
    bool refValid;
    bool useCanReceiveVotes = false;

    constructor() {}

    function setRefValid(bool _refValid) public {
        refValid = _refValid;
    }

    function setUseCanReceiveVotes(bool _useCanReceiveVotes) public {
        useCanReceiveVotes = _useCanReceiveVotes;
    }

    function isProposalRefValid(uint256) public view override returns (bool) {
        return refValid;
    }

    function canReceiveVotes(
        uint256 _proposalId,
        Tally memory tally
    ) public view override returns (bool, ToucanReceiver.ErrReason) {
        if (useCanReceiveVotes) {
            return super.canReceiveVotes(_proposalId, tally);
        }

        return (true, ErrReason.None);
    }
}
