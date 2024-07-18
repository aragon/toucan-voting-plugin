# Setting security stacks

[The Layer Zero docs](https://docs.layerzero.network/v2/developers/evm/configuration/default-config#checking-default-configuration) provide details on how to configure the security properties of your OApps. Here is a practical set of steps.

## Overview

We will be calling the `ILayerZeroEndpointV2` with `setConfig` on _both_ chains for _each_ application.

Recall our setup for toucan:

- 3 on the voting chain:

  - ToucanRelay (S,R\*)
  - AdminXChain (R)
  - OFTTokenBridge (S,R)

- 3 on the execution chain:
  - ToucanReceiver (S\*, R)
  - ActionRelay (S)
  - GovernanceOFTAdapter (S,R)

S indicates the contract is OAppSender
R indicates the contract is OAppReceiver

- indicates the contract is technically a Sender/Receiver, but does not have logic to use the functionality yet.

See [Itemising The Calls](#itemising-the-calls) for the list of calls we need to make.

The format of `setConfig` is:

```c
// Chain A set config for SEND
A__endpoint.setConfig(
    A__OApp,
    A__SendLibAddr,
    [
      ULNConfig,
      ExecutorConfig
    ]
);

// Chain B set config for RECEIVE
B__endpoint.setConfig(
  B__OApp,
  B__ReceiveLibAddr,
  [
    ULNConfig
  ]
)
```

## Set the libraries

- Set the send and receive libraries for each endpoint - you don't need to do this if set already but the libraries should match your config.
- Note that this needs to be done for every `OAppSender` and `OAppReceiver`,

```c
endpoint.setSendLibrary(app, eid, sendLibAddresss);
endpoint.setReceiveLibrary( /* "" */, receiverLibAddress);
```

## Define config

There are 2 types of config that have the following encoding as bytes

Executor config:
`[type==1(8)]tuple(uint32 maxMessageSize, address executorAddress)`

ULN Config:
`[type==2(8)]tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)`

The bare minimum is to grab a [DVN](https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses) and [Executor](https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts) from the places below and set 1 DVN and 1 confirmation: this should only be used for testing.

Scroll to the bottom of [this tx](https://testnet.layerzeroscan.com/tx/0x44a3c4bb622b76e64e894e5d0b857964d694db7cb6c2bd52cba6c37b25d85c2e) to see an example config.

## Set sender and receiver

For each OApp that implements Send it needs send and receipt config to be set. So contracts that ONLY implement receive don't need to set send config.

In our case that means:

- AdminXChain, ToucanReceiver

Don't need to set send config.

## Itemising the calls

Relay -> Receiver:

- Send on relay
- Receive on receiver

ActionRelay -> AdminXchain

- Send on relay
- Receive on admin

Adapter <-> Bridge

- Send on Adapter
- Send on Bridge
- Receive on Adapter
- Recieve on Bridge
