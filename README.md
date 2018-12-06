# Native Hyperledger Fabric
This project prepares **Hyperledger Fabric** to run natively on OSX without using Docker. Smart contracts are
written in Go and installed as Go Plugins, so no needs for chaincode Docker containers. The same approach may be 
applied on other platforms.

## Build Fabric Native
Follow instruction from Fabric document [Setting Up Development Environment](https://hyperledger-fabric.readthedocs.io/en/latest/dev-setup/devenv.html) to install the necessary tools (execpt Docker) and download the source code. Note that you may also get the source code from [Fabric GitHub Mirror](https://github.com/hyperledger/fabric).

Once you have got the source code, you can build Fabric for OSX platform as follow:
```
cd $GOPATH/src/github.com/hyperledger/fabric
make native
```

The binaries are stored in `.build/bin`. Since we want to use Go Plugin, we need to explicitly enable it
when we build `peer` as it is disabled by default. Rebuild the `peer` with the following commands:
```
rm .build/bin/peer 
GO_TAGS+=pluginsenabled make peer
```

At this point, all the required binaries to run Fabric natively on OSX are ready in `.build/bin` directory. You may copy them to you working directory or run them directly from here. The rest of this document assumes the following 2 environment variables:
```
export FABBIN=$GOPATH/src/github.com/hyperledger/fabric/.build/bin
export FABCONF=$GOPATH/src/github.com/hyperledger/fabric/sampleconfig
```

The first variable `FABBIN` points to the location where Fabric binaries are, and the second one `FABCONF` points to the sample configuration shipped with Fabric source code. You may use your own configuration and replace as appropriate throughout this document.

## Smart Contract as Go Plugin
We use System Chaincode to implement our smart contract. There are differences between a System Chaincode and a Docker-based Chaincode. Specifically a System Chaincode differs on: 
1. Go package must be named `main`
2. A constructor `func New() shim.Chaincode`
3. Function `Init` is called when the **peer** joins a channel but no ledger-write should be performed in this function as there is no transaction context like `instantiate` for Docker-based chaincode
4. Only 1 instance of a System Chaincode exists (not an instance per channel though that might be more desirable in some use cases)
5. There is no `upgrade` transaction buit-in 

We are going to demonstrate this by using **example02** chaincode shipped with Fabric source at **examples/chaincode/go/example02**. The modified code is in the file [example02](https://github.com/chainforce/native-fabric/blob/master/example02.go), which includes the new package name and the constructor. We also changed the `Init` function into 2 functions: a mandatory `Init` interface implementation and a new `initialize` function to set the smart contract's variables.

Build the plugin as follow:
```
cd $GOPATH/src/github.com/hyperledger/fabric/examples/chaincode/go/example02
go build -buildmode=plugin -o example02.so chaincode.go
```

That will produce `example02.so`, which is our smart contract plugin binary.

## Configure Peer with Smart Contract Plugin
We need to make some changes to **core.yaml** to include the smart contract plugin.
1. Enable the plugin under `chaincode.system`
```
chaincode:
  system:
    example02: enable
```

2. Add the plugin configuration to `chaincode.systemPlugins`
```
chaincode:
  systemPlugins:
      - enabled: true
        name: example02
        path: /src/github.com/hyperledger/fabric/examples/chaincode/go/example02/example02.so
        invokableExternal: true
        invokableCC2CC: true
```

The `path` property points to the smart contract plugin binary that we built above. 

## Launch Fabric Network
At this point, we are ready to bring up the network natively on OSX platform. We are setting up a simple network consists of 1 **peer** and 1 **orderer** using the `sampleconfig` at `FABCONF`. You can examine the configuration in `$FABCONF\configtx.yaml`.

Open up a Terminal window and enter the following command to start up the **orderer**
```
FABRIC_CFG_PATH=$FABCONF ORDERER_GENERAL_GENESISPROFILE=SampleSingleMSPSolo $FABBIN/orderer
```

Open up another Terminal window to start up the **peer*
```
FABRIC_CFG_PATH=$FABCONF FABRIC_LOGGING_SPEC=gossip=warn:msp=warn:debug $FABBIN/peer node start
```

Now we will create a channel **mych** so that we can transact using our smart contract. We use `configtxgen` tool to generate a configuration transaction based on `$FABCONF\configtx.yaml` specification. 

Open another Terminal window and run the following command to generate a channel create configuration transaction:
```
FABRIC_CFG_PATH=$FABCONF $FABBIN/configtxgen -profile SampleSingleMSPChannel -outputCreateChannelTx mych.tx -channelID mych
```

The output is `mych.tx`, which contains the data to create a channel. We use that to send a channel creation transaction to the network:
```
FABRIC_CFG_PATH=$FABCONF $FABBIN/peer channel create -f mych.tx -c mych -o 127.0.0.1:7050
```

The output of this command is `mych.block`, which is a configuration block containing the artifacts about the channel that we can use to instruct appropriate peers to join the channel. Since our simple network has only 1 peer, we tell it to join the channel:
```
FABRIC_CFG_PATH=$FABCONF $FABBIN/peer channel join -b mych.block
```

Now the network (1 peer and 1 orderer) is ready to process transactions according to our smart contract **example02** on channel `mych`. Note that we don't have to **install** and **instantiate** this smart contract like a Docker-based one.

## Send Transactions to Smart Contract
We can send all the transactions as in the normal **example02** smart contract. However, as mentioned above, with System Chaincode, we have to explicitly initialize our smart contract assets first, as implemented in our **example02** plugin.
```
FABRIC_CFG_PATH=$FABCONF $FABBIN/peer chaincode invoke -C mych -n example02 -c '{"Args":["initialize", "a", "100", "b","200"]}'
```

After successfully initialized, we can send any other **example02**'s transactions. For example:
```
FABRIC_CFG_PATH=$FABCONF $FABBIN/peer chaincode invoke -C mych -n example02 -c '{"Args":["transfer","a","b","10"]}'

FABRIC_CFG_PATH=$FABCONF $FABBIN/peer chaincode query -C mych -n example02 -c '{"Args":["query","a"]}'
```

## Clean up
Fabric stores data at `/var/hyperledger/production`. We also created `mych.tx` and `mych.block`. You can rerun the network, and it will pick up from the last time. However, if you are done and want to clean up everything, run the following commands:
```
rm -rf /var/hyperledger/production
rm mych.tx mych.block
```
