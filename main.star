contract_deployer = import_module("./contract-deployment/contract-deployer.star")

def run(plan, args):
    contract_deployer.deploy_teleporter_messenger(plan, "http://172.16.4.7:9650/ext/bc/2ueGjm3eo2NCWsY9E3PRDgtEDejBkm5MXustM9epEGE1yPn1Mf/rpc", "myblockchain")
    