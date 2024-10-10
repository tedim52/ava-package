utils = import_module("./utils.star")

BUILDER_SERVICE_NAME = "builder"
SUBNET_CREATION_CODE_PATH = "/tmp/subnet-creator-code"
GENESIS_GENERATOR_CODE_PATH = "/tmp/genesis-generator-code"

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

    subnet_genesis = plan.upload_files("./static-files/example-subnet-genesis.json", name="subnet-genesis")
    subnet_genesis_with_teleporter = plan.upload_files("./static-files/example-subnet-genesis-with-teleporter.json", name="subnet-genesis-with-teleporter")

    genesis_generator_code = plan.upload_files("./genesis-generator-code", name="genesis-generator-code")

    subnet_creator_code = plan.upload_files("./subnet-creator-code", name="subnet-creator-code")

    plan.add_service(
        name=BUILDER_SERVICE_NAME,
        config=ServiceConfig(
            image = "golang:1.22.2",
            entrypoint=["sleep", "99999"],
            files={
                GENESIS_GENERATOR_CODE_PATH: genesis_generator_code,
                SUBNET_CREATION_CODE_PATH: subnet_creator_code,
                "/tmp/node-config": node_cfg,
                "/tmp/subnet-genesis": Directory(
                    artifact_names=[subnet_genesis,subnet_genesis_with_teleporter],
                ),
            }
        )
    )

def generate_genesis(plan, network_id, num_nodes, vmName):
    plan.exec(
        service_name=BUILDER_SERVICE_NAME,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", "-c", "cd {0} && go run main.go {1} {2} {3}".format(GENESIS_GENERATOR_CODE_PATH, network_id, num_nodes, vmName)]
        )
    )

    for index in range(0, num_nodes):
        plan.exec(
            service_name = BUILDER_SERVICE_NAME,
            recipe = ExecRecipe(
                command = ["cp", "/tmp/node-config/config.json", "/tmp/data/node-{0}/config.json".format(index)]
            )
        )

    genesis_data = plan.store_service_files(
        service_name = BUILDER_SERVICE_NAME,
        src = "/tmp/data",
        name="generated-genesis-data"
    )

    vm_id = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/data/vmId.txt")

    return genesis_data, vm_id

def create_subnet_and_blockchain_for_l1(plan, uri, num_nodes, is_elastic, vm_id, chain_name):
    plan.exec(
        service_name = BUILDER_SERVICE_NAME,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cd /tmp/subnet-creator-code && go run main.go {0} {1} {2} {3} {4}".format(uri, vm_id, chain_name, num_nodes, is_elastic)]
        )
    )

    subnetId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/subnetId.txt")
    chainId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/chainId.txt")
    allocations = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/allocations.txt")
    genesisChainId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/genesisChainId.txt")

    assetId, transformationId, exportId, importId = None, None, None, None
    if is_elastic:
        assetId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/assetId.txt")
        transformationId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/transformationId.txt")
        exportId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/exportId.txt")
        importId = utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/importId.txt")

    validatorIds = []
    for index in range (0, num_nodes):
        validatorIds.append(utils.read_file_from_service(plan, BUILDER_SERVICE_NAME, "/tmp/subnet/node-{0}/validator_id.txt".format(index)))
    
    return subnetId, chainId, validatorIds, allocations, genesisChainId, assetId, transformationId, exportId, importId
