#!/usr/bin/bash

receiver_address=$1
blockchain_id=$2

cast call --rpc-url http://127.0.0.1:9650/ext/bc/${blockchain_id}/rpc ${receiver_address} "lastMessage()(string)"