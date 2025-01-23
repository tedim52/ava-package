builder = import_module("./builder/builder.star")
node_launcher = import_module("./node_launcher.star")
l1 = import_module("./l1.star")
relayer = import_module("./relayer/relayer.star")
contract_deployer = import_module("./contract-deployment/contract-deployer.star")
bridge_frontend = import_module("./bridge-frontend/bridge-frontend.star")
utils = import_module("./utils.star")
constants = import_module("./constants.star")

# additional services
observability = import_module('./observability/observability.star')
faucet = import_module('./faucet/faucet.star')
tx_spammer = import_module('./tx_spammer.star')
block_explorer = import_module('./block-explorer/block-explorer.star')

# TODO: add a docstring
def run(plan, args):
    node_cfg = args['node-cfg']
    network_id = args['node-cfg']['network-id']
    num_nodes = args['num-nodes']
    chain_configs = args.get('chain-configs', [])
    additional_services = args.get('additional-services', {})
    codespace_name = args.get('codespace-name', "")
    
    is_etna_deployment = utils.contains_etna_l1(chain_configs)
    subnet_evm_binary_url = utils.get_subnet_evm_url(plan, chain_configs)
    avalanche_go_image = utils.get_avalanchego_img(chain_configs)

    # create builder, responsible for scripts to generate genesis, create subnets, create blockchains
    builder.init(plan, node_cfg)

    # generate genesis for primary network (p-chain, x-chain, c-chain)
    genesis, subnet_evm_id = builder.generate_genesis(plan, network_id, num_nodes, constants.DEFAULT_VM_NAME) # TODO: return vm_ids for all vm names

    # start avalanche node network
    node_info, bootnode_name = node_launcher.launch(
        plan,
        network_id,
        genesis,
        avalanche_go_image,
        num_nodes,
        subnet_evm_id,
        subnet_evm_binary_url,
        codespace_name
    )
    plan.print("Node Info: {0}".format(node_info))
    
    # create l1s
    l1_info = {}
    for idx, chain in enumerate(chain_configs):
        is_etna_chain = chain.get('etna', False)
        chain_name, chain_info = l1.launch_l1(plan, node_info, bootnode_name, num_nodes, chain["name"], subnet_evm_id, idx, chain["network-id"], is_etna_chain)

        # teleporter messenger needs to be manually deployed on etna l1s
        if is_etna_chain:
            teleporter_messenger_address = contract_deployer.deploy_teleporter_messenger(plan, chain_info["RPCEndpointBaseURL"], chain_name)
            plan.print(teleporter_messenger_address)

        teleporter_registry_address = contract_deployer.deploy_teleporter_registry(plan, chain_info["RPCEndpointBaseURL"], chain_name)
        plan.print("Teleporter Registry Address on {0}: {1}".format(chain_name, teleporter_registry_address))
        chain_info["TeleporterRegistryAddress"] = teleporter_registry_address

        erc_token_name = chain.get("erc-20-token-name", "")
        if erc_token_name != "":
            erc20_token_address = contract_deployer.deploy_erc20_token(plan, chain_info["RPCEndpointBaseURL"], "TOK")
            chain_info["ERC20TokenAddress"] = erc20_token_address
            chain_info["ERC20TokenName"] = erc_token_name 
            plan.print("ERC20 Token Address on {0}: {1}".format(chain_name, erc20_token_address))

        chain_info["NetworkId"] = chain["network-id"]
        l1_info[chain_name] = chain_info

    # deploy erc20 token bridges
    launch_relayer = False
    for idx, chain in enumerate(chain_configs):
        if "erc20-bridge-config" not in chain:
            continue

        launch_relayer = True
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

    if launch_relayer == True:
        relayer.launch_relayer(plan, node_info[bootnode_name]["rpc-url"], l1_info, is_etna_deployment)

    # additional services:
    if additional_services.get("observability", False) == True:
        observability.launch_observability(plan, node_info)

    if additional_services.get("ictt-frontend", False) == True and len(l1_info) >= 2 and launch_relayer == True:
        bridge_frontend.launch_bridge_frontend(plan, l1_info, chain_configs)
    
    c = 0
    for chain_name, chain in l1_info.items():
        if additional_services.get("tx-spammer", False) == True:
            tx_spammer.spam_transactions(plan, chain["RPCEndpointBaseURL"], chain_name)

        if additional_services.get("block-explorer", False) == True:
            blockscout_frontend_url = block_explorer.launch_blockscout(plan, chain_name, chain["GenesisChainId"], chain["RPCEndpointBaseURL"], chain["WSEndpointBaseURL"], codespace_name, c)
            l1_info[chain_name]["PublicExplorerUrl"] = blockscout_frontend_url
        c += 1

    if additional_services.get("faucet", False) == True and len(l1_info) > 0:
        faucet.launch_faucet(plan, l1_info)

    return l1_info