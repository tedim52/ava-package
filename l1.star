builder = import_module('./builder/builder.star')
utils = import_module('./utils.star')
node_launcher = import_module('./node_launcher.star')

def launch_l1(plan, node_info, bootnode_name, num_nodes, chain_name, vm_id, l1_counter, chain_id, isEtna):
    # TODO: support elastic l1 subnets
    # create subnet and blockchain for this l1
    node_rpc_uri = node_info[bootnode_name]["rpc-url"] 
    public_node_rpc_uri = node_info[bootnode_name]["public-rpc-url"] 
    chain_info = builder.create_subnet_and_blockchain_for_l1(plan, node_rpc_uri, public_node_rpc_uri, num_nodes, isEtna, vm_id, chain_name, l1_counter, chain_id)
    
    subnet_id = chain_info["SubnetId"]
    chain_id = chain_info["BlockchainId"]

    # store subnet id
    if l1_counter == 0:
        utils.append_contents_to_file(plan, builder.BUILDER_SERVICE_NAME, "/tmp/data/subnet_ids.txt", subnet_id)
    else:   
        utils.append_contents_to_file(plan, builder.BUILDER_SERVICE_NAME, "/tmp/data/subnet_ids.txt", ",{0}".format(subnet_id))
    
    # instruct all nodes to track this l1
    for node_name, node in node_info.items():
        node_launcher.track_subnet(plan, node_name, node, chain_id)
        plan.print("{0} tracking subnet {1}".format(node_name, subnet_id))

    # wait for bootnode to come online to ensure health
    node_launcher.wait_for_health(plan, bootnode_name)

    return chain_name, chain_info

def create_subnet_and_blockchain_for_l1(plan, uri, public_uri, num_nodes, is_etna, vm_id, chain_name, l1_counter, chain_id):
    create_subnet_cmd ="cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7} {8}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "create")
    plan.print(create_subnet_cmd)
    plan.exec(
        description="Creating subnet and blockchain for {0}".format(chain_name),
        service_name = builder.BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6} {7}".format(uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "create")]
        )
    )

    add_validators_cmd = "cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7} {8}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "addvalidators")
    plan.print(add_validators_cmd)
    plan.exec(
        description="Adding validators for {0}".format(chain_name),
        service_name = builder.BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6} {7}".format(uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "addvalidators")]
        )
    )


    subnet_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/subnetId.txt".format(l1_counter))
    blockchain_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/blockchainId.txt".format(subnet_id))
    hex_blockchain_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/hexChainId.txt".format(subnet_id))
    allocations = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/allocations.txt".format(subnet_id))
    genesis_chain_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/genesisChainId.txt".format(subnet_id))

    validator_ids = []
    for index in range (0, num_nodes):
        validator_ids.append(utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/node-{1}/validator_id.txt".format(subnet_id, index)))

    http_trimmed_uri = uri.replace("http://", "", 1)
    return {
        "SubnetId": subnet_id,
        "BlockchainId": blockchain_id, 
        "BlockchainIdHex": hex_blockchain_id,
        "GenesisChainId": genesis_chain_id,
        "VM": vm_id,
        "Allocations": allocations,
        "ValidatorIds": validator_ids,
        "RPCEndpointBaseURL": "{0}/ext/bc/{1}/rpc".format(uri, blockchain_id),
        "PublicRPCEndpointBaseURL": "{0}/ext/bc/{1}/rpc".format(public_uri, blockchain_id),
        "WSEndpointBaseURL": "ws://{0}/ext/bc/{1}/ws".format(http_trimmed_uri, blockchain_id),
    }