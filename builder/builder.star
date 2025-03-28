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

    poa_contracts = plan.upload_files(src="./static-files/contracts/", name="poa-contracts")
    morpheusvm_genesis = plan.upload_files(src="./static-files/example-morpheusvm-genesis.json.tmpl", name="morpheusvm-genesis")

    plan.add_service(
        name=BUILDER_SERVICE_NAME,
        config=ServiceConfig(
            image =ImageBuildSpec(
                image_name="tedim52/builder:latest",
                build_context_dir="./"
            ),
            entrypoint=["sleep", "9999999"],
            files={
                "/tmp/node-config": node_cfg,
                "/tmp/genesis-files": Directory(
                    artifact_names=[morpheusvm_genesis],
                ),
                "/tmp/contracts/": poa_contracts
            },
            env_vars={
                "BASE_TMP_PATH": "/tmp",
                "BASE_GENESIS_PATH": "/tmp/genesis-files"
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

    # the genesis data artifact is a directory of data containing information about the primary network, all the node information (ids, signer/stakings, keys etc.)
    # this artifact gets placed onto each node downstream and are configured based on this data
    # do a `kurtosis files inspect <enclave name> generated-genesis-data` to view whats inside
    genesis_data = plan.store_service_files(
        service_name = BUILDER_SERVICE_NAME,
        src = "/tmp/data",
        name="generated-genesis-data"
    )

    vm_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/data/vmId.txt")

    return genesis_data, vm_id

def create_subnet_and_blockchain_for_l1(plan, uri, public_uri, maybe_codespace_uri, num_nodes, vm_id, chain_name, l1_counter, chain_id):
    result = plan.exec(
        description="Creating subnet and blockchain for {0}".format(chain_name),
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6}".format(uri, vm_id, chain_name, num_nodes, l1_counter, chain_id, "createsubnetandblockchain")]
        ),
    )

    plan.exec(
        description="Converting subnet to l1 for {0}".format(chain_name),
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6}".format(uri, vm_id, chain_name, num_nodes, l1_counter, chain_id, "convertsubnettol1")]
        ),
    )

    subnet_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/subnetId.txt".format(l1_counter))
    blockchain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/blockchainId.txt".format(subnet_id))
    hex_blockchain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/hexChainId.txt".format(subnet_id))
    allocations = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/allocations.txt".format(subnet_id))
    genesis_chain_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/{0}/genesisChainId.txt".format(subnet_id))

    validator_ids = []

    http_trimmed_uri = uri.replace("http://", "", 1)

    l1_config = {
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
    
    if maybe_codespace_uri != "":
        l1_config["CodespaceRPCEndpointBaseURL"] = "{0}/ext/bc/{1}/rpc".format(maybe_codespace_uri, blockchain_id)

    return l1_config

def initialize_validator_set(plan, uri, num_nodes, vm_id, chain_name, l1_counter, chain_id):
    result = plan.exec(
        description="Initializing validator set for blockchain for {0}".format(chain_name),
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "./subnet-creator {0} {1} {2} {3} {4} {5} {6}".format(uri, vm_id, chain_name, num_nodes, l1_counter, chain_id, "initvalidatorset")]
        )
    )