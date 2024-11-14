builder = import_module("./builder.star")
utils = import_module("./utils.star")
node_launcher = import_module("./node_launcher.star")
l1 = import_module("./l1.star")
relayer = import_module("./relayer/relayer.star")
contract_deployer = import_module("./contract-deployment/contract-deployer.star")
bridge_frontend = import_module("./frontend/bridge-frontend.star")

# additional services
observability = import_module('./observability/observability.star')
tx_spammer = import_module('./tx_spammer.star')
block_explorer = import_module('./blockexplorer/block-explorer.star')
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
        chain_name, chain_info = l1.launch_l1(plan, node_info, bootnode_name, num_nodes, chain["name"], subnet_evm_id, idx, chain["network-id"])

        # deploy teleporter registry contract
        teleporter_registry_address = contract_deployer.deploy_teleporter_registry(plan, chain_info["RPCEndpointBaseURL"], chain_name)
        plan.print("Teleporter Registry Address on {0}: {1}".format(chain_name, teleporter_registry_address))
        chain_info["TeleporterRegistryAddress"] = teleporter_registry_address

        # launch tx spammer for this chain
        # tx_spammer.spam_transactions(plan, chain_info["RPCEndpointBaseURL"], tx_pk, idx)

        chain_info["NetworkId"] = chain["network-id"]
        l1_info[chain_name] = chain_info

    # start relayer
    relayer.launch_relayer(plan, node_info[bootnode_name]["rpc-url"], l1_info)

    # deploy erc20 bridges
    for idx, chain in enumerate(chain_configs):
        if "erc20-bridge-config" not in chain:
            continue

        bridge_config = chain["erc20-bridge-config"]
        source_chain_name = chain["name"]

        erc20_token_address = contract_deployer.deploy_erc20_token(plan, l1_info[source_chain_name]["RPCEndpointBaseURL"], "TOK")
        l1_info[source_chain_name]["ERC20TokenAddress"] = erc20_token_address
        plan.print("ERC20 Token Address on {0}: {1}".format(source_chain_name, erc20_token_address))

        token_home_address = contract_deployer.deploy_token_home(plan, l1_info[source_chain_name]["RPCEndpointBaseURL"], "TOK", teleporter_registry_address, erc20_token_address)
        l1_info[source_chain_name]["TokenHomeAddress"] = token_home_address
        plan.print("Token Home Address on {0} for {1}: {2}".format(source_chain_name, "TOK", token_home_address))

        for idx, dest_chain_name in enumerate(bridge_config["destinations"]):
            token_remote_address = contract_deployer.deploy_token_remote(plan, l1_info[dest_chain_name]["RPCEndpointBaseURL"], "TOK", l1_info[dest_chain_name]["TeleporterRegistryAddress"], l1_info[source_chain_name]["BlockchainIdHex"], token_home_address)
            l1_info[dest_chain_name]["TokenRemoteAddress"] = token_remote_address


    # start prom and grafana
    observability.launch_observability(plan, node_info)
    
    bridge_frontend.launch_bridge_frontend(plan, l1_info, chain_configs)

    # additional services:

    # TODO: start a faucet

    # TODO: start blockscout explorer

    return l1_info
   