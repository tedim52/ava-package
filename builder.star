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
    # subnet_genesis_with_teleporter = plan.upload_files("./static-files/example-subnet-genesis-with-teleporter.json", name="subnet-genesis-with-teleporter")
    # subnet_genesis_with_teleporter_tmpl = read_file("./static-files/example-subnet-genesis-with-teleporter.json.tmpl")
    subnet_genesis_with_teleporter = plan.upload_files("./static-files/example-subnet-genesis-with-teleporter.json.tmpl", "subnet_genesis_with_teleporter")
    # subnet_genesis_with_teleporter = plan.render_templates(
    #     config={
    #         "example-subnet-genesis-with-teleporter.json": struct(
    #             template=subnet_genesis_with_teleporter_tmpl,
    #             data={
    #                 "NetworkId":
    #             },
    #         )
    #     },
    #     name="subnet-genesis-with-teleporter",
    # )

    genesis_generator_code = plan.upload_files("./genesis-generator-code", name="genesis-generator-code")

    subnet_creator_code = plan.upload_files("./subnet-creator-code", name="subnet-creator-code")

    plan.add_service(
        name=BUILDER_SERVICE_NAME,
        config=ServiceConfig(
            image = "golang:1.22.8",
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
