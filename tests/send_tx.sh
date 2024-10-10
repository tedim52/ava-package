#!/bin/zsh

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <blockchainId> <portNum>"
    exit 1
fi

blockchainId=$1
portNum=$2

# Define the URL
url="http://127.0.0.1:${portNum}/ext/bc/${blockchainId}/rpc"

read -r -d '' payload << EOF
{
    "jsonrpc":"2.0",
    "method":"eth_sendTransaction",
    "params":[
        {
            "from": "0x8d6699fe55244cb471837f3f80e602d0ccf2665e",
            "to": "0x0x8db97c7cece249c2b98bdc0226cc4c2a57bf52fc",
            "gas": "0x76c0", 
            "gasPrice": "0x9184e72a000", 
            "value": "0x9184e72a", 
            "data": "0x"
        }
    ],
    "id":1
}
EOF

read -r -d '' payload << EOF
{
    "jsonrpc":"2.0",
    "method":"eth_getBalance",
    "params":["0x8d6699fe55244cb471837f3f80e602d0ccf2665e", "latest"],
    "id":1
}'
EOF

# Make the curl request
response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    --data "$payload" \
    $url)

# Output the response
echo "Response: $response" 
