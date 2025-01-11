utils = import_module("../utils.star")

BUILDER_SERVICE_NAME = "builder"

def init(plan, node_cfg_map):
    node_cfg_template = read_file("./static-files/config.json.tmpl")

    cfg_template_data = {
        "PluginDirPath": "/avalanchego/build/plugins/",
        "NetworkId": node_cfg_map["network-id"],
        "StakingEnabled": node_cfg_map["staking-enabled"],
        "HealthCheckFrequency": node_cfg_map["health-check-frequency"],
    }

    node_cfg = plan.render_templates(
        config= {
            "config.json": struct(
                template = node_cfg_template,
                data = cfg_template_data,
            ),
        },
        name="node-cfg"
    )

    subnet_genesis_with_teleporter_tmpl = plan.upload_files("./static-files/example-subnet-genesis-with-teleporter.json.tmpl", "subnet_genesis_with_teleporter")
    etna_contracts = plan.upload_files("./static-files/contracts/")

    plan.add_service(
        name=BUILDER_SERVICE_NAME,
        config=ServiceConfig(
            # image =ImageBuildSpec(
            #     image_name="tedim52/builder:latest",
            #     build_context_dir="./"
            # ),
            image="tedim52/builder:new",
            entrypoint=["sleep", "9999999"],
            files={
                "/tmp/node-config": node_cfg,
                "/tmp/subnet-genesis": Directory(
                    artifact_names=[subnet_genesis_with_teleporter_tmpl],
                ),
                "/tmp/contracts/": etna_contracts
            }
        )
    )

def generate_genesis(plan, network_id, num_nodes, vmName):
    plan.exec(
        service_name=BUILDER_SERVICE_NAME,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", "-c", "./genesis-generator {0} {1} {2}".format(network_id, num_nodes, vmName)]
        ),
        description="Generating genesis for primary network with args network id '{0}', num_nodes '{1}', vm '{2}'".format(network_id, num_nodes, vmName),
    )

    for index in range(0, num_nodes):
        plan.exec(
            service_name = BUILDER_SERVICE_NAME,
            recipe = ExecRecipe(
                command = ["cp", "/tmp/node-config/config.json", "/tmp/data/node-{0}/config.json".format(index)]
            ),
            description="Creating config files for each node",
        )

    genesis_data = plan.store_service_files(
        service_name = BUILDER_SERVICE_NAME,
        src = "/tmp/data",
        name="generated-genesis-data"
    )

    vm_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/data/vmId.txt")

    return genesis_data, vm_id

def create_subnet_and_blockchain_for_l1(plan, uri, public_uri, num_nodes, is_etna, vm_id, chain_name, l1_counter, chain_id):
    # create_subnet_cmd ="cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7} {8}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "create")
    # plan.print(create_subnet_cmd)
    result = plan.exec(
        description="Creating subnet and blockchain for {0}".format(chain_name),
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6} {7}".format(uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "create")]
        )
    )

    plan.print("Create output: {0}".format(result["output"]))

    # add_validators_cmd = "cd {0} && go run main.go {1} {2} {3} {4} {5} {6} {7} {8}".format(builder.SUBNET_CREATION_CODE_PATH, uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "addvalidators")
    # plan.print(add_validators_cmd)
    plan.exec(
        description="Adding validators for {0}".format(chain_name),
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6} {7}".format(uri, vm_id, chain_name, num_nodes, is_etna, l1_counter, chain_id, "addvalidators")]
        )
    )


    subnet_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/subnetId.txt".format(l1_counter))
    blockchain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/blockchainId.txt".format(subnet_id))
    hex_blockchain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/hexChainId.txt".format(subnet_id))
    allocations = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/allocations.txt".format(subnet_id))
    genesis_chain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/genesisChainId.txt".format(subnet_id))

    plan.store_service_files(
        service_name=BUILDER_SERVICE_NAME,
        name="l1-configs",
        src="/tmp/subnet/",
        description="storing 1 configs",
    )

    validator_ids = []
    for index in range (0, num_nodes):
        validator_ids.append(utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/node-{1}/validator_id.txt".format(subnet_id, index)))

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