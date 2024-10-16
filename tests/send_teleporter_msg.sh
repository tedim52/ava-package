#!/usr/bin/bash

sender_address=$1
receiver_address=$2
blockchain_id=$3
pk=56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027

cast send --rpc-url http://127.0.0.1:9650/ext/bc/${blockchain_id}/rpc --private-key ${pk} ${sender_address} "sendMessage(address,string)" ${receiver_address} "Hello"