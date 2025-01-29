constants = import_module("./constants.star")

# reads the given file in service without the new line
def read_file_from_service(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {}".format(filename)]
        )
    )
    return output["output"]

def append_contents_to_file(plan, service_name, filename, content):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "echo -n \"{0}\" >> {1}".format(content, filename)]
        ),
        description="Appending {0} to '{1}' in {2}".format(content, filename, service_name)
    )
    return output["output"]

def write_contents_to_file(plan, service_name, filename, content):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "echo \"{0}\" > {1}".format(content, filename)]
        )
    )
    return output["output"]

def get_subnet_evm_url(plan, chain_configs):
    cpu_arch_result = plan.run_sh(
        description="Determining cpu architecture",
        run="/bin/sh -c \"[ \"$(uname -m | tr -d '\n')\" = \"arm64\" ] || [ \"$(uname -m | tr -d '\n')\" = \"aarch64\" ] && echo -n arm64 || echo -n amd64\""
    )
    cpu_arch = cpu_arch_result.output
    plan.print("Detected CPU arch: {0}".format(cpu_arch))
    if contains_etna_l1(chain_configs):
        return constants.ETNA_SUBNET_EVM_BINARY_URL_FMT_STR.format(cpu_arch)
    else:
        return constants.DEFAULT_SUBNET_EVM_BINARY_URL_FMT_STR.format(cpu_arch)

def get_avalanchego_img(chain_configs):
    if contains_etna_l1(chain_configs):
        return constants.ETNA_AVALANCHEGO_IMAGE
    else:
        return constants.DEFAULT_AVALANCHEGO_IMAGE

def contains_etna_l1(chain_configs):
    for chain in chain_configs:
        if chain.get("etna") == True:
            return True
    return False

def get_vm_name(chain_configs):
    if len(chain_configs) == 0:
        return "subnetevm"
    return chain_configs[0]["vm"]