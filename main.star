builder = import_module("./builder.star")
utils = import_module("./utils.star")
node_launcher = import_module("./node_launcher.star")
l1 = import_module("./l1.star")
relayer = import_module("./relayer/relayer.star")

# additional services
observability = import_module('./observability/observability.star')
tx_spammer = import_module('./tx_spammer.star')
blockscout = import_module('./blockscout/blockscout.star')
faucet = import_module('./faucet.star')

AVALANCHEGO_IMAGE = "avaplatform/avalanchego:v1.11.11"
SUBNET_EVM_BINARY_URL = "https://github.com/ava-labs/subnet-evm/releases/download/v0.6.10/subnet-evm_0.6.10_linux_arm64.tar.gz"

def run(plan, args):
    node_cfg = args['node-cfg']
    networkd_id = args['base-network-id']
    num_nodes = args['num-nodes']
    chain_configs = args['chain-configs']

    # create builder, responsible for scripts to generate genesis, create subnets, create blockchains
    builder.init(plan, node_cfg)

    # generate genesis for primary network (p-chain, x-chain, c-chain)
    genesis, subnet_evm_id = builder.generate_genesis(plan, networkd_id, num_nodes, "subnetevm") # TODO: return vm_ids for all vm names
    plan.print("VM ID FOR subnetevm: {0}".format(subnet_evm_id))

    # start avalanche node network
    node_info, bootnode_name = node_launcher.launch(
        plan,
        genesis,
        AVALANCHEGO_IMAGE,
        num_nodes,
        subnet_evm_id,
        SUBNET_EVM_BINARY_URL, 
    )
    
    # create l1s
    tx_pk = "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
    l1_info = {}
    for idx, chain in enumerate(chain_configs):
        chain_name, chain_info = l1.launch_l1(plan, node_info, bootnode_name, num_nodes, chain["name"], subnet_evm_id, idx)
        l1_info[chain_name] = chain_info
        
        # launch tx spammer for this chain
        tx_spammer.spam_transactions(plan, chain_info["RPCEndpointBaseURL"], tx_pk, idx)

    # start relayer
    relayer.launch_relayer(plan, node_info[bootnode_name]["rpc-url"], l1_info)

    # additional services

    # start prom and grafana
    observability.launch_observability(plan, node_info)

    # start blockscout

    # start a faucet

    # start teleporter frontend

    # start bridge frontend UI frontend

    return l1_info
   