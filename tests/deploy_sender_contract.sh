#!/bin/bash

# Check if blockchain_id is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <blockchain_id>"
    exit 1
fi

blockchain_id=$1
pk=56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027

# Ensure that the Solidity file exists before running the command
contract_path="/Users/tewodrosmitiku/craft/sandbox/avalanche-starter-kit/contracts/interchain-messaging/send-receive/senderOnCChain.sol:SenderOnCChain"
if [ ! -f "${contract_path%:*}" ]; then
    echo "Contract file not found: ${contract_path%:*}"
    exit 1
fi

# Execute the forge create command
forge create --rpc-url http://127.0.0.1:9650/ext/bc/$blockchain_id/rpc --private-key $pk $contract_path
