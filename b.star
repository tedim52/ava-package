blockexplorer = import_module("./block-explorer/block-explorer.star")

def run(plan, args):
    blockexplorer.launch_blockscout(
        plan,
        "myblockchain",
        555555,
        "http://172.16.0.6:9650/ext/bc/2UxBKnQjd9DN87VSYsZ5smJN7Y2iA8cAKU7Wx1rHr849Kui9AD/rpc",
        "ws://172.16.0.6:9650/ext/bc/2UxBKnQjd9DN87VSYsZ5smJN7Y2iA8cAKU7Wx1rHr849Kui9AD/ws",
    )