    # frontend = import_module("./frontend/bridge-frontend.star")
faucet = import_module("./faucet/faucet.star")

PK = "d28fb31486d7bd9f7fbe4c9087939ce765d4c3acf577756b1f9af9702956a063"

def run(plan, args):
    l1_info = {
        "myblockchain":{
            "ERC20TokenAddress": "0x5aa01B3b5877255cE50cc55e8986a7a5fe29C70e",
            "NetworkId": 555555,
            "PublicRPCEndpointBaseURL": "http://127.0.0.1:9650/ext/bc/pAEnY2ZCApG9GXNkJ37g8NBbSvRt7JJJZxDZXZwc2p3xReuzC/rpc",
        },
    }
    faucet.launch_faucet(plan, l1_info, PK)
