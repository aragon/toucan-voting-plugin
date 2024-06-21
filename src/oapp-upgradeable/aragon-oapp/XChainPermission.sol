// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {IOAppCore, ILayerZeroEndpointV2} from "@lz-oapp/interfaces/IOAppCore.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "@utils/converters.sol";

/// @dev this is a work in progress, it is not yet used in the codebase
interface IXChainPermission is IPermissionCondition {
    enum Protocol {
        Unknown,
        LayerZeroV2
    }

    struct XChainData {
        Protocol protocol;
        address remoteSender;
        uint256 protocolRemoteChainId;
    }

    function isRemoteSender(address _where, XChainData memory _data) external view returns (bool);

    function grantCrossChainPermission(
        address _who,
        address _where,
        bytes32 _permissionId,
        XChainData calldata _data
    ) external;

    error XChainNotAuthorized(address who, address where, bytes32 permissionId, XChainData data);

    event XChainGranted(XChainData data);
}

contract XChainMessagerRole {
    bytes32 public constant XCHAIN_MESSAGER_ROLE = keccak256("XCHAIN_MESSAGER_ROLE");
}

contract LayerZeroXChainPermissionAdapter is IXChainPermission {
    using SafeCast for uint256;

    function isRemoteSender(address _where, XChainData memory _data) public view returns (bool) {
        bytes32 peer = IOAppCore(_where).peers(_data.protocolRemoteChainId.toUint32());
        return bytes32ToAddress(peer) == _data.remoteSender;
    }

    constructor() {
        // nothing to do here
    }

    function isGranted(
        address,
        address _where,
        bytes32,
        bytes calldata _data
    ) public view returns (bool) {
        // decode the data
        XChainData memory xchaindata = abi.decode(_data, (XChainData));
        return isRemoteSender(_where, xchaindata);
    }

    /// need to have the admin permission on the IOAppCore contract
    function grantCrossChainPermission(
        address _who,
        address _where,
        bytes32,
        XChainData calldata _data
    ) public /* needs an auth */ {
        IOAppCore(_where).setPeer(_data.protocolRemoteChainId.toUint32(), addressToBytes32(_who));
        emit XChainGranted(_data);
    }
}
