#!/bin/bash
FABRIC_CFG_PATH=$FABCONF \
FABRIC_LOGGING_SPEC=gossip=warn:msp=warn:debug \
CORE_CHAINCODE_LOGGING_LEVEL=debug \
CORE_CHAINCODE_LOGGING_SHIM=debug \
$FABBIN/peer node start
