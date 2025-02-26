builder = import_module('../builder/builder.star')
utils = import_module('../utils.star')
node_launcher = import_module('../node_launcher.star')

def launch_l1(plan, node_info, bootnode_name, num_nodes, chain_name, vm_id, l1_counter, chain_id, isEtna):
    # create subnet and blockchain for this l1
    node_rpc_uri = node_info[bootnode_name]["rpc-url"] 
    public_node_rpc_uri = node_info[bootnode_name]["public-rpc-url"] 
    maybe_codespace_node_uri = node_info[bootnode_name]["codespace-rpc-url"] 
    chain_info = builder.create_subnet_and_blockchain_for_l1(plan, node_rpc_uri, public_node_rpc_uri, maybe_codespace_node_uri, num_nodes, isEtna, vm_id, chain_name, l1_counter, chain_id)
    
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
