// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

contract DAOMock is IDAO {
    address internal constant NO_CONDITION = address(0);

    event Granted(
        bytes32 indexed permissionId,
        address indexed here,
        address where,
        address indexed who,
        address condition
    );

    event Revoked(
        bytes32 indexed permissionId,
        address indexed here,
        address where,
        address indexed who
    );

    bool public hasPermissionReturnValueMock;

    function setHasPermissionReturnValueMock(bool _hasPermissionReturnValueMock) external {
        hasPermissionReturnValueMock = _hasPermissionReturnValueMock;
    }

    function hasPermission(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes memory _data
    ) external view override returns (bool) {
        (_where, _who, _permissionId, _data);
        return hasPermissionReturnValueMock;
    }

    function applyMultiTargetPermissions(
        PermissionLib.MultiTargetPermission[] calldata _items
    ) external {
        for (uint256 i; i < _items.length; ) {
            PermissionLib.MultiTargetPermission memory item = _items[i];

            if (item.operation == PermissionLib.Operation.Grant) {
                grant({_where: item.where, _who: item.who, _permissionId: item.permissionId});
            } else if (item.operation == PermissionLib.Operation.Revoke) {
                revoke({_where: item.where, _who: item.who, _permissionId: item.permissionId});
            } else if (item.operation == PermissionLib.Operation.GrantWithCondition) {
                grantWithCondition({
                    _where: item.where,
                    _who: item.who,
                    _permissionId: item.permissionId,
                    _condition: IPermissionCondition(item.condition)
                });
            }

            unchecked {
                ++i;
            }
        }
    }

    function grant(address _where, address _who, bytes32 _permissionId) public {
        (_where, _who, _permissionId);

        emit Granted({
            permissionId: _permissionId,
            here: msg.sender,
            where: _where,
            who: _who,
            condition: NO_CONDITION
        });
    }

    function revoke(address _where, address _who, bytes32 _permissionId) public {
        (_where, _who, _permissionId);

        emit Revoked({permissionId: _permissionId, here: msg.sender, where: _where, who: _who});
    }

    function grantWithCondition(
        address _where,
        address _who,
        bytes32 _permissionId,
        IPermissionCondition _condition
    ) public {
        emit Granted({
            permissionId: _permissionId,
            here: msg.sender,
            where: _where,
            who: _who,
            condition: address(_condition)
        });
    }

    function getTrustedForwarder() public pure override returns (address) {
        return address(0);
    }

    function setTrustedForwarder(address _trustedForwarder) external pure override {
        (_trustedForwarder);
    }

    function setMetadata(bytes calldata _metadata) external pure override {
        (_metadata);
    }

    function execute(
        bytes32 callId,
        Action[] memory _actions,
        uint256 allowFailureMap
    ) external override returns (bytes[] memory execResults, uint256 failureMap) {
        emit Executed(msg.sender, callId, _actions, allowFailureMap, failureMap, execResults);
    }

    function deposit(
        address _token,
        uint256 _amount,
        string calldata _reference
    ) external payable override {
        (_token, _amount, _reference);
    }

    function setSignatureValidator(address _signatureValidator) external pure override {
        (_signatureValidator);
    }

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) external pure override returns (bytes4) {
        (_hash, _signature);
        return 0x0;
    }

    function registerStandardCallback(
        bytes4 _interfaceId,
        bytes4 _callbackSelector,
        bytes4 _magicNumber
    ) external pure override {
        (_interfaceId, _callbackSelector, _magicNumber);
    }
}
