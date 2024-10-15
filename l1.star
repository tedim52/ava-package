builder = import_module('./builder.star')
utils = import_module('./utils.star')
node_launcher = import_module('./node_launcher.star')

def launch_l1(plan, node_info, bootnode_name, num_nodes, chain_name, vm_id, l1_counter):
    # TODO: support elastic l1 subnets
    # create subnet and blockchain for this l1
    chain_info = create_subnet_and_blockchain_for_l1(plan, node_info[bootnode_name]["rpc-url"], num_nodes, False, vm_id, chain_name, l1_counter)
    
    subnet_id = chain_info["SubnetId"]

    # store subnet id
    if l1_counter == 0:
        utils.append_contents_to_file(plan, builder.BUILDER_SERVICE_NAME, "/tmp/data/subnet_ids.txt", subnet_id)
    else:   
        utils.append_contents_to_file(plan, builder.BUILDER_SERVICE_NAME, "/tmp/data/subnet_ids.txt", ",{0}".format(subnet_id))
    
    # instruct all nodes to track this l1
    for node_name, node in node_info.items():
        node_launcher.track_subnet(plan, node_name, node)
        plan.print("{0} tracking subnet {1}".format(node_name, subnet_id))

    # wait for bootnode to come online to ensure health
    node_launcher.wait_for_health(plan, bootnode_name)

    return chain_name, chain_info

def create_subnet_and_blockchain_for_l1(plan, uri, num_nodes, is_elastic, vm_id, chain_name, l1_counter):
    plan.exec(
        description="Creating subnet and blockchain for {0}".format(chain_name),
        service_name = builder.BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_elastic, l1_counter, "create")]
        )
    )

    plan.exec(
        description="Adding validators for {0}".format(chain_name),
        service_name = builder.BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_elastic, l1_counter, "addvalidators")]
        )
    )

    subnet_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/subnetId.txt".format(l1_counter))
    chain_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/chainId.txt".format(subnet_id))
    allocations = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/allocations.txt".format(subnet_id))
    genesis_chain_id = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/genesisChainId.txt".format(subnet_id))

    validator_ids = []
    for index in range (0, num_nodes):
        validator_ids.append(utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/node-{1}/validator_id.txt".format(subnet_id, index)))

    http_trimmed_uri = uri.replace("http://", "", 1)
    return {
        "SubnetId": subnet_id,
        "BlockchainId": chain_id, 
        "VM": vm_id,
        "Allocations": allocations,
        "ValidatorIds": validator_ids,
        "RPCEndpointBaseURL": "{0}/ext/bc/{1}/rpc".format(uri, chain_id),
        "WSEndpointBaseURL": "ws://{0}/ext/bc/{1}/ws".format(http_trimmed_uri, chain_id),
    }