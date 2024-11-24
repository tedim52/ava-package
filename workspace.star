block_explorer = import_module('./block-explorer/block-explorer.star')


def run(plan, args):
    chain_name="myblockchain"
    chain_id = "555555"
    chain_rpc_url="http://172.16.0.5:9650/ext/bc/2pdmG7j4LwsQNwH6MQaUMRywk4j3Sv6WEXCRkrvtHA71wuGT3m/rpc"
    chain_ws_url="ws://172.16.0.5:9650/ext/bc/2pdmG7j4LwsQNwH6MQaUMRywk4j3Sv6WEXCRkrvtHA71wuGT3m/ws"
    block_explorer.launch_blockscout(plan, chain_name, chain_id, chain_rpc_url, chain_ws_url)