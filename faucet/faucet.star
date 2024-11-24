

def launch_faucet(plan, chain_info, funded_private_key):
    evm_chain_info, erc_20_tokens = get_faucet_cfg_info(chain_info)

    config_file_tmpl = read_file(src="./config.json.tmpl")
    config_file_artifact = plan.render_templates(
        config={
            "config.json": struct(
                template=config_file_tmpl,
                data={
                    "EVMChains": evm_chain_info,
                    "ERC20Tokens": erc_20_tokens,
                }
            )
        },
        name="faucet-config-file"
    )

    plan.add_service(
        name="faucet",
        config=ServiceConfig(
            image="tedim52/avalanche-faucet:latest",
            files={
                "/avalanche-faucet/config/": config_file_artifact,
            },
            env_vars={
                "PK": funded_private_key,
                "CAPTCHA_SECRET": "Google ReCaptcha V3 Secret",
                "NODE_ENV": "development",
            },
            ports={
                "faucet": PortSpec(
                    number=8000,
                    application_protocol="http",
                    transport_protocol="TCP",
                )
            },
            public_ports ={
                "faucet": PortSpec(
                    number=8000,
                    application_protocol="http",
                    transport_protocol="TCP",
                )
            },

        )
    )

    recipe_result = plan.wait(
        service_name = "faucet",
        recipe=GetHttpRequestRecipe(
            port_id = "faucet",
            endpoint = "/health",
        ),
        field="code",
        assertion = "==",
        target_value = 200,
        interval = "1s",
        timeout = "1m",
        description = "Waiting for a faucet to be healthy" ,
    )

def get_faucet_cfg_info(chain_info):
    evm_chains =[]
    erc_20_tokens = []

    for chain_name, chain in chain_info.items():
        evm_chains.append({
            "Name": chain_name,
            "RPCUrl": chain["RPCEndpointBaseURL"],
            "ChainID": chain["NetworkId"],
        })
        if "ERC20TokenAddress" in chain:
            erc_20_tokens.append({
                "ID": "{0}{1}".format("TOK", chain_name),
                "HostID": chain_name,
                "ERC20ContractAddress": chain["ERC20TokenAddress"],
            })
    return evm_chains, erc_20_tokens