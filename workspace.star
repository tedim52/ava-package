# frontend = import_module("./frontend/bridge-frontend.star")
frontend = import_module("./frontend/bridge-frontend-dev.star")

def run(plan, args):
    l1_info = {
        "myblockchain":{
            "ERC20TokenAddress": "0x5aa01B3b5877255cE50cc55e8986a7a5fe29C70e",
            "TokenHomeAddress": "0x5DB9A7629912EBF95876228C24A848de0bfB43A9",
            "NetworkId": 555555,
            "PublicRPCEndpointBaseURL": "http://127.0.0.1:9650/ext/bc/pAEnY2ZCApG9GXNkJ37g8NBbSvRt7JJJZxDZXZwc2p3xReuzC/rpc",
            "TeleporterRegistryAddress": "0x17ab05351fc94a1a67bf3f56ddbb941ae6c63e25",
        },
        "mysecondblockchain":{
            "TokenRemoteAddress": "0x5aa01B3b5877255cE50cc55e8986a7a5fe29C70e",
            "NetworkId": 666666,
            "PublicRPCEndpointBaseURL": "http://127.0.0.1:9650/ext/bc/2ZeZBwxri5yNwH9LGRkxZDdzvBAH7z1AURbW9y7rGsWrqZtqTv/rpc",
            "TeleporterRegistryAddress": "0x17ab05351fc94a1a67bf3f56ddbb941ae6c63e25",
        }
    }
    chain_config = [
        {
            "name": "myblockchain",
            "vm": "subnetevm",
            "network-id": 555555,
            "erc20-bridge-config": {
                "token-name": "TOK",
                "destinations": ["mysecondblockchain"]
            }
        },
        {
            "name": "mysecondblockchain",
            "vm": "subnetevm",
            "network-id": 666666,
        }
    ]
    frontend.launch_bridge_frontend(plan, l1_info, chain_config)
