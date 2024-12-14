builder = import_module("./builder.star")
utils = import_module("./utils.star")

NODE_ID_PATH = "/tmp/data/node-{0}/node_id.txt"
BUILDER_SERVICE_NAME = "builder"

EXECUTABLE_PATH = "avalanchego"
ABS_PLUGIN_DIRPATH = "/avalanchego/build/plugins/"
ABS_DATA_DIRPATH = "/tmp/data/"
RPC_PORT_ID = "rpc"
RPC_PORT_NUM = 9650
PUBLIC_IP = "127.0.0.1"

STAKING_PORT_NUM = 9651
NODE_NAME_PREFIX = "node-"

def launch(
    plan, 
    genesis, 
    image, 
    node_count,  
    vmId, 
    custom_subnet_vm_url):

    bootstrap_ips = []
    bootstrap_ids = []
    nodes = []
    launch_commands = []
    node_info = {}

    services = {}
    for index in range(0, node_count):
        node_name = NODE_NAME_PREFIX + str(index)

        node_data_dirpath = ABS_DATA_DIRPATH + node_name
        node_config_filepath = node_data_dirpath + "/config.json"

        launch_node_cmd = [
            "nohup",
            "/avalanchego/build/" + EXECUTABLE_PATH,
            "--genesis-file=/tmp/data/genesis.json",
            "--data-dir=" + node_data_dirpath,
            "--config-file=" + node_config_filepath,
            "--http-host=0.0.0.0",
            "--staking-port=" + str(STAKING_PORT_NUM),
            "--http-port=" + str(RPC_PORT_NUM),
            "--log-dir=/tmp/",
            "--network-health-min-conn-peers=" + str(node_count - 1),
        ]

        plan.print("Creating node {0} with command {1}".format(node_name, launch_node_cmd))

        public_ports = {}
        public_ports["rpc"] = PortSpec(number=RPC_PORT_NUM + index * 2, transport_protocol="TCP", wait=None)
        public_ports["staking"] = PortSpec(number=STAKING_PORT_NUM + index * 2, transport_protocol="TCP", wait=None)

        log_files = ["main.log", "C.log", "X.log", "P.log", "vm-factory.log"]
        log_files_cmds = ["touch /tmp/{0}".format(log_file) for log_file in log_files]
        log_file_cmd = " && ".join(log_files_cmds)

        node_files = {
            "/tmp/data": genesis
        }

        node_service_config = ServiceConfig(
            image=image,
            entrypoint=["/bin/sh", "-c", log_file_cmd + " && cd /tmp && tail -F *.log"],
            ports={
                "rpc": PortSpec(number=9650, transport_protocol="TCP", wait=None),
                "staking": PortSpec(number=9651, transport_protocol="TCP", wait=None)
            },
            files=node_files,
            public_ports=public_ports,
        )

        services[node_name] = node_service_config
        launch_commands.append(launch_node_cmd)

    nodes = plan.add_services(services)

    for index in range(0, node_count):
        node_name = NODE_NAME_PREFIX + str(index)

        node = nodes[node_name]
        launch_node_cmd = launch_commands[index]

        if bootstrap_ips:
            launch_node_cmd.append("--bootstrap-ips={0}".format(",".join(bootstrap_ips)))
            launch_node_cmd.append("--bootstrap-ids={0}".format(",".join(bootstrap_ids)))

        plan.exec(
            service_name=node_name,
            recipe=ExecRecipe(
                command=["mkdir", "-p", ABS_PLUGIN_DIRPATH]
            )
        )

        if custom_subnet_vm_url:
            download_to_path_and_untar(plan, node_name, custom_subnet_vm_url, ABS_PLUGIN_DIRPATH + vmId)

        plan.exec(
            description="Restarting node {0} with new launch node cmd {1}".format(index, launch_node_cmd),
            service_name=node_name,
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", " ".join(launch_node_cmd) + " >/dev/null 2>&1 &"],
            )
        )

        bootstrap_ips.append("{0}:{1}".format(node.ip_address, 9651))
        bootstrap_id_file = NODE_ID_PATH.format(index)
        bootstrap_id = utils.read_file_from_service(plan, "builder", bootstrap_id_file)
        bootstrap_ids.append(bootstrap_id)

        node_info[node_name] = {
            "rpc-url": "http://{0}:{1}".format(node.ip_address, RPC_PORT_NUM),
            "public-rpc-url": "http://{0}:{1}".format(PUBLIC_IP, RPC_PORT_NUM),
            "launch-command": launch_node_cmd,
        }

    wait_for_health(plan, "node-" + str(node_count - 1))

    # public_rpc_urls = []
    # public_rpc_urls = ["http://{0}:{1}".format(PUBLIC_IP, RPC_PORT_NUM + index * 2) for index, node in
    #                        enumerate(nodes)]

    return node_info, NODE_NAME_PREFIX + "0"

def track_subnet(plan, node_name, node_info, chain_id):
    subnet_ids = utils.read_file_from_service(plan, builder.BUILDER_SERVICE_NAME, "/tmp/data/subnet_ids.txt")
    node_info["launch-command"].append("--track-subnets={0}".format(subnet_ids))

    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c",
                        """grep -l 'avalanchego' /proc/*/status | awk -F'/' '{print $3}' | while read -r pid; do kill -9 "$pid"; done"""]
        ),
        description="Killing avalanche go process on {0}".format(node_name)
    )

    subnet_evm_config = read_file("./static-files/subnetevm-config.json")
    node_data_dirpath = ABS_DATA_DIRPATH + node_name
    subnet_evm_config_dir_path = "{0}/configs/chains/{1}".format(node_data_dirpath, chain_id)
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "mkdir -p {0} && echo '{1}' >> {0}/config.json".format(subnet_evm_config_dir_path, subnet_evm_config)]
        ),
        description="Creating chain config for {0} on {1}".format(chain_id, node_name)
    )

    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", " ".join(node_info["launch-command"]) + " >/dev/null 2>&1 &"],
        ),
        description="Restarting avalanche go on {0}".format(node_name),
    )

def wait_for_health(plan, node_name):
    response = plan.wait(
        service_name=node_name,
        recipe=PostHttpRequestRecipe(
            port_id=RPC_PORT_ID,
            endpoint="/ext/health",
            content_type="application/json",
            body="{ \"jsonrpc\":\"2.0\", \"id\" :1, \"method\" :\"health.health\"}",
            extract={
                "healthy": ".result.healthy",
            }
        ),
        field="extract.healthy",
        assertion="==",
        target_value=True,
        timeout="5m",
    )

def download_to_path_and_untar(plan, node_name, url, dest):
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c",
                     "apt update --allow-insecure-repositories && apt-get install curl -y --allow-unauthenticated"]
        )
    )

    download_path = "/static_files/subnet_vm.tar.gz"
    plan.print("Downloading {0} to {1}".format(url, download_path))
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "mkdir -p /static_files/ && curl -L {0} -o {1}".format(url, download_path)]
        )
    )

    plan.print("Untaring {0}".format(download_path))
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "mkdir -p /avalanchego/build/plugins && tar -zxvf {0} -C /static_files/".format(download_path)]
        )
    )

    # Move the extracted binary to the destination
    plan.print("Moving extracted binary to {0}".format(dest))
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "mv /static_files/subnet-evm {0}".format(dest)]
        )
    )    






