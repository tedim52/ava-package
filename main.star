builder = import_module("./builder.star")
utils = import_module("./utils.star")
node_launcher = import_module("./node_launcher.star")
l1 = import_module("./l1.star")
relayer = import_module("./relayer/relayer.star")
contract_deployer = import_module("./contract-deployment/contract-deployer.star")
bridge_frontend = import_module("./frontend/bridge-frontend.star")

# additional services
observability = import_module('./observability/observability.star')
faucet = import_module('./faucet/faucet.star')
tx_spammer = import_module('./tx_spammer.star')
block_explorer = import_module('./block-explorer/block-explorer.star')

DEFAULT_AVALANCHEGO_IMAGE = "avaplatform/avalanchego:v1.11.11"
ETNA_DEVNET_AVALANCHEGO_IMAGE = "avaplatform/avalanchego:v1.12.0-fuji"
SUBNET_EVM_BINARY_URL = "https://github.com/ava-labs/subnet-evm/releases/download/v0.6.10/subnet-evm_0.6.10_linux_arm64.tar.gz"
AMD64_SUBNET_EVM_BINARY_URL = "https://github.com/ava-labs/subnet-evm/releases/download/v0.6.10/subnet-evm_0.6.10_linux_amd64.tar.gz"
ETNA_SUBNET_EVM_BINARY_URL = "https://github.com/ava-labs/subnet-evm/releases/download/v0.6.12/subnet-evm_0.6.12_linux_arm64.tar.gz"

# TODO: Use a separate private key for faucet
PK = "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"

def run(plan, args):
    node_cfg = args['node-cfg']
    networkd_id = args['node-cfg']['network-id']
    num_nodes = args['num-nodes']
    chain_configs = args['chain-configs']

    image = AVALANCHEGO_IMAGE
    subnet_evm_binary_url = SUBNET_EVM_BINARY_URL

    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output
    if cpu_arch == "amd64":
       subnet_evm_binary_url = AMD64_SUBNET_EVM_BINARY_URL

    image = DEFAULT_AVALANCHEGO_IMAGE
    subnet_evm_binary_url = SUBNET_EVM_BINARY_URL
    useEtnaAssets = False
    if contains_etna_l1(chain_configs):
        useEtnaAssets = True
        image = ETNA_DEVNET_AVALANCHEGO_IMAGE 
        subnet_evm_binary_url = ETNA_SUBNET_EVM_BINARY_URL

    # create builder, responsible for scripts to generate genesis, create subnets, create blockchains
    builder.init(plan, node_cfg)

    # generate genesis for primary network (p-chain, x-chain, c-chain)
    genesis, subnet_evm_id = builder.generate_genesis(plan, networkd_id, num_nodes, "subnetevm") # TODO: return vm_ids for all vm names
    plan.print("VM ID FOR subnetevm: {0}".format(subnet_evm_id))

    # start avalanche node network
    node_info, bootnode_name = node_launcher.launch(
        plan,
        genesis,
        image,
        num_nodes,
        subnet_evm_id,
        subnet_evm_binary_url
    )
    
    # create l1s
    l1_info = {}
    for idx, chain in enumerate(chain_configs):
        isEtna = chain.get('etna', False)
        chain_name, chain_info = l1.launch_l1(plan, node_info, bootnode_name, num_nodes, chain["name"], subnet_evm_id, idx, chain["network-id"], isEtna)

        # deploy teleporter messenger contract
        teleporter_messenger_address = contract_deployer.deploy_teleporter_messenger(plan, chain_info["RPCEndpointBaseURL"], chain_name)
        plan.print(teleporter_messenger_address)

        # deploy teleporter registry contract
        teleporter_registry_address = contract_deployer.deploy_teleporter_registry(plan, chain_info["RPCEndpointBaseURL"], chain_name)
        plan.print("Teleporter Registry Address on {0}: {1}".format(chain_name, teleporter_registry_address))
        chain_info["TeleporterRegistryAddress"] = teleporter_registry_address

        chain_info["NetworkId"] = chain["network-id"]
        l1_info[chain_name] = chain_info

    # start relayer
    # relayer.launch_relayer(plan, node_info[bootnode_name]["rpc-url"], l1_info)

    # # deploy erc20 bridges
    # for idx, chain in enumerate(chain_configs):
    #     if "erc20-bridge-config" not in chain:
    #         continue

    #     bridge_config = chain["erc20-bridge-config"]
    #     source_chain_name = chain["name"]

    #     erc20_token_address = contract_deployer.deploy_erc20_token(plan, l1_info[source_chain_name]["RPCEndpointBaseURL"], "TOK")
    #     l1_info[source_chain_name]["ERC20TokenAddress"] = erc20_token_address
    #     plan.print("ERC20 Token Address on {0}: {1}".format(source_chain_name, erc20_token_address))

    #     token_home_address = contract_deployer.deploy_token_home(plan, l1_info[source_chain_name]["RPCEndpointBaseURL"], "TOK", teleporter_registry_address, erc20_token_address)
    #     l1_info[source_chain_name]["TokenHomeAddress"] = token_home_address
    #     plan.print("Token Home Address on {0} for {1}: {2}".format(source_chain_name, "TOK", token_home_address))

    #     for idx, dest_chain_name in enumerate(bridge_config["destinations"]):
    #         token_remote_address = contract_deployer.deploy_token_remote(plan, l1_info[dest_chain_name]["RPCEndpointBaseURL"], "TOK", l1_info[dest_chain_name]["TeleporterRegistryAddress"], l1_info[source_chain_name]["BlockchainIdHex"], token_home_address)
    #         l1_info[dest_chain_name]["TokenRemoteAddress"] = token_remote_address

    # # additional services:
    # observability.launch_observability(plan, node_info)

    # bridge_frontend.launch_bridge_frontend(plan, l1_info, chain_configs)

    # faucet.launch_faucet(plan, l1_info, "0x{0}".format(PK))

    for chain_name, chain in l1_info.items():
        # launch tx spammer for this chain
        tx_spammer.spam_transactions(plan, chain["RPCEndpointBaseURL"], PK, chain_name)

        # launch block explorer for this chain
        block_explorer.launch_blockscout(plan, chain_name, chain["GenesisChainId"], chain["RPCEndpointBaseURL"], chain["WSEndpointBaseURL"])

    return l1_info
   
def contains_etna_l1(chain_configs):
    for chain in chain_configs:
        if chain.get("etna") == True:
            return True
    return False