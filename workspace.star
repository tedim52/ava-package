# frontend = import_module("./frontend/bridge-frontend.star")
frontend = import_module("./frontend/bridge-frontend-dev.star")

def run(plan, args):
    l1_info = {
        "myblockchain":{
            "ERC20TokenAddress": "134231",
            "TokenHomeAddress": "134231",
            "NetworkId": 6666,
            "PublicRPCEndpointBaseURL": "23421",
            "TeleporterRegistryAddress": "341423",
        },
        "mysecondblockchain":{
            "TokenRemoteAddress": "1234123",
            "NetworkId": 55555,
            "PublicRPCEndpointBaseURL": "23421",
            "TeleporterRegistryAddress": "341423",
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
