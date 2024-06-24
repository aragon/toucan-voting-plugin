# Permissions in XChain

## A fundamental mismatch

One key differentiator between OSx permissions and how a lot of EVM permissions work can be explained by a solidity 101 example. 

Specifically, say you have a contract, how would you ensure only specific addresses can call it?

The easiest approach is obvious to anyone:

```js
public mapping(address who => bool) canCall;

function protected() external {
    require(canCall[msg.sender], "can't call");
}

function whitelist(address _who) external {
    canCall[_who] = true;
}
```

Super simple. And it's (more or less) the OZ Ownable approach. Because it's so simple, we see this patter _all the time_ in crypto, including in Layer Zero.

Compare this to OSx (or Zodiac, or OZ AccessManager, or Llama), which defines more advanced permission conditions but which typically doesn't inline the permission logic. This is federated out to another contract which defines advanced (and standardised) permissions.

```js
bytes32 constant PROTECTED_ID = keccak256("PROTECTED");

function osxProtected() auth(PROTECTED_ID) external {}
```

The downside of the above approach is in situations like LayerZero where the contracts we are provided define a simple auth model in various places, and we wish to use our standardised, more flexible permissions system.

## Permissions in OApps

Currently, layerZero defines several internal permissions:

1. On the OApp contracts, there are contract _owners_ using OZ Ownable that can execute `onlyOwner` functions.
2. On the LzEndpoint, there is a _delegate_ that can configure the endpoint settings for that OApp.
3. On cross-chain calls, there are _peers_ which are addresses on remote chains that are setup to send messages to this OApp.

![image](https://github.com/aragon/toucan-voting-plugin/assets/45881807/38e31a86-8a58-4ea8-8d5a-6ed80c6265a3)

Put another way, you have _multiple ways to manage the permissions system in oapps and it's easy to forget one_.

**I'm of the view that, in a complex, cross-chain system, the OSx solution of having one, standardised way to control permissions in the entire system is preferable to having to manage multiple independent setters.**

Moreover, each of these addresses is a point of failure in the whole system. The DAO should ultimately be in control of the entire OApp, and so we should not mandate priveledged parties. 

## Problem 1: Multiple Permissions on the same chain.

Solutions to (1) and (2) just involve reducing the permissions from multiple setters to a single workflow. There's 2 obvious ways to do this:

### Solution A: DAO owns it all:

- Set the delegage to the DAO
- Transfer ownership to the DAO

**Advantages**:

- Requires no code changes to the layer zero contracts
- Super simple and then the OApp is controlled by `DAO.execute`

**Disadvantages**: 

- Zero flexibility, even small changes to layer zero would need to go through the whole DAO proposal workflow, instead of having different bodies for OApp management.
- Doesn't directly use Aragon permission management meaning you still technically have multiple permission systems in place.

### Solution B: Use the Aragon Permissions system:

The technical implementation of this can be seen in [AragonOAppAuthorizable](./AragonOAppAuthorizable.sol). In short we have 4 parts parts:

1. A single permission that is created `OAPP_ADMINISTRATOR`.
2. The using of that permission in place of `onlyOwner`
3. An `execute` function, protected by `OAPP_ADMINISTRATOR` that allows admins to make arbitrary calls from the OApp.*
4. Setting the OApp's address as the delegate address.

*On later thought, we need to discard this as is a potentially dangerous attack vector. An example would be if the OApp has MINT and BURN roles on a voting token: the OAPP Admin could then control the supply.

The consequence of (3) and (4) is that now, the _only_ way to make changes to the OApp, is via the Aragon permissions system, meaning it is entirely controlled by the DAO.

Note as well: the EndpointV2 implementation of LayerZero allows the OApp to be its own delegate, meaninging it is redundant to delegate to `address(this)`. 

**Advantages**:

- Can have multiple parties that can administer the OApp
- Everything goes through the permission manager system

**Disadvantages**: 

- Requires code changes to the LayerZero contracts
- Not usable outside of Aragon context
- Setting the delegate happens on the endpoint, so strictly speaking, you still have a second permission system.
- `executeSelf` is very broad, and needs to be used with caution.
- `OAPP_ADMINISTRATORS` could change the delegate to an address other than `address(dao)` which would circumvent the PM system.
    - It is trivial to change this though - we simply revert `setDelegate`:
```js
/// @notice We prohibit changing the delegate as this would allow admins to bypass the permission model of the OApp.
function setDelegate(address) public view auth(OAPP_ADMINISTRATOR_ID) {
    revert SetDelegateProhibited();
}
```
However, in general my opinion is that the permissions system should be flexible. 

## Problem 2: Peers, XChain Permissions and IOAppCore

A much harder problem is the notion of peers in OApps, and the `IOAppCore` interface constraints to which we need to adhere to guarantee liveness. 

A *peer* is simply an address on another chain that has permission to call our OApp. Peers are _yet another permission management system in layer zero_ using the simple approach:

```js
function setPeer(uint32 _eid, bytes32 _peer) public virtual auth(OAPP_ADMINISTRATOR_ID) {
    peers[_eid] = _peer;
    emit PeerSet(_eid, _peer);
}

function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
    bytes32 peer = peers[_eid];
    if (peer == bytes32(0)) revert NoPeer(_eid);
    return peer;
}
```

Note, crucially that the peer is held against an `_eid` which is a layer zero 32bit chain identifier (**NOT** the `block.chainid`). We need this for the simple reason that a malicious actor with the same address on a different chain should not be able to call our OApp.

Layer Zero actually enforces this for us by checking the `Origin`:

```js
struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}
```
This is a very basic primitive that allows us to query the:
- Chain ID the message was sent from
- The OApp the message was sent from

And then, in the `lzReceive` function (the entrypoint for xchain calls):

```js
function lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) public payable virtual {
    // Ensures that only the endpoint can attempt to lzReceive() messages to this OApp.
    if (address(endpoint) != msg.sender) revert OnlyEndpoint(msg.sender);

    // Ensure that the sender matches the expected peer for the source endpoint.
    if (_getPeerOrRevert(_origin.srcEid) != _origin.sender)
```

Let's restate the problem here: Layer Zero enforces, in a very sensible way, a permissions system for cross chain calls that is entirely separate from the rest of the Aragon permissions system. 

If we _do_ want to make changes here, we have to be mindful that the LayerZero endpoint contract _will_ expect certain functions to be available on our OApp.

### Solution 1: Who cares?

A solution is to dismiss this as a problem. `setPeer` is controlled by the DAO under `OAPP_ADMINISTRATOR` role (it could even have its own separate role for additional protection). Why change what isn't broken.

**Advantages**: 

- No further code changes needed.
- No digression from `IOAppCore`.
- DAO ultimately has the full control of the permissions system.

**Disadvantages**:

- Our cross-chain permissions are tightly coupled to layerZero, by using `setPeer` and `eid` instead of `grant` and and universal chainId.

### Solution 2: A first stab a XChain permissions

What if we wanted an answer to a universal standard for OSx XChain permissions? What might that look like?

It would need to meet the following:

1. It should be compatible with `IOAppCore`.
2. It should be forward compatible with other messaging brokers.
3. It should leverage the Aragon Permissions system.

### An AragonLzAdapter

The Adapter in this case needs to act as a bridge between IOAppCore and some unified permissions system.

Fortunately, we have a unified permissions system (`PermissionManager`), and we can pass extra data as a permission condition.

We could leverage PermissionConditions to ensure that a permission is set correctly. 

Recall, in the case of layerZero:
- `setPeer` is called on the OApp, which writes the peer to a mapping held against the eid. 
- OApp receiver implements a public `lzReceive` function. This is protected in 2 ways:
    1. Caller must be the endpoint
    2. Caller must pass an `Origin` struct that contains the original calling address and the source chain, this is checked against the peer.

Doing this with permission conditions would involve:
1. Change lzReceive so that it is protected by `auth(CROSS_CHAIN_RECEIVE_CALLER_ID)`, which can be granted to the endpoint.
2. Add `grantWithCondition` when setting `CROSS_CHAIN_RECEIVE_CALLER`. This condition will link to a contract that implements `IPermissionCondition`.

### Implementation

See [`LayerZeroXChainPermissionAdapter`](./XChainPermision.sol) for an implementation. 

The Idea is to standardise the interface for cross chain permissions and wrap the layerZero setter and getter. 

We also standardise the error, role and event so that contracts can implement it.

This has the advantage of standardising the workflow even with different message brokers. The disadvantage mostly relate to verbosity and a slightly more complicated setup:
- You need to deploy a permission condition
- You need to grant permission on the condition contract
- You need to modify LzRecieve
