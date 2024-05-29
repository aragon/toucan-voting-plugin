pragma solidity ^0.8.20;

import {ToucanReceiver} from "src/crosschain/toucanRelay/ToucanReceiver.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

contract MockToucanReceiver is ToucanReceiver {
    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) ToucanReceiver(_governanceToken, _lzEndpoint, _dao, _votingPlugin) {}

    // no overriden methods yet
}
