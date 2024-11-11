WEB_APPS_IMAGE = "tedim52/avalanche-web-apps:latest"

def launch_bridge_frontend(plan, l1_info, chain_config):
    # parameterize chain definition file for each chain
    chain_cfg_artifacts = []
    chain_cfg_tmpl = read_file(src="./blockchain-config.ts.tmpl")
    for chain_name, chain_info in l1_info.items():
        chain_cfg_artifact = plan.render_templates(
            config={
                "{0}.ts".format(chain_name): struct(
                    template=chain_cfg_tmpl,
                    data={
                        "NETWORK_ID": chain_info["NetworkId"],
                        "BLOCKCHAIN_NAME": chain_name,
                        "NETWORK_NAME": chain_name,
                        "RPC_URL": chain_info["PublicRPCEndpointBaseURL"],
                        "TELEPORTER_REGISTRY_ADDRESS": chain_info["TeleporterRegistryAddress"],
                    },
                )
            },
            name="{0}-bridge-config-artifact".format(chain_name)
        )
        chain_cfg_artifacts.append(chain_cfg_artifact)

    src_blockchain_id, dest_blockchain_id, token_address, token_cfgs = get_bridge_config_info(plan, l1_info, chain_config)

    # parameterize constants file with token configs
    constants_tmpl = read_file(src="./constants.ts.tmpl")
    constants_artifact = plan.render_templates(
        config={
            "constants.ts": struct(
                template=constants_tmpl,
                data={
                    "Chains": get_chain_list(plan, l1_info), # assume only two chains in the bridge right now
                    "Tokens": token_cfgs,
                }
            )
        },
        name="bridge-constants-artifact"
    )
    
    # parameterize ictt page 
    page_tmpl = read_file(src="./page.tsx.tmpl")
    page_artifact = plan.render_templates(
        config={
            "page.tsx": struct(
                template=page_tmpl,
                data={
                    "TOKEN_ADDRESS": token_address,
                    "SOURCE_CHAIN_ID": src_blockchain_id,
                    "DEST_CHAIN_ID": dest_blockchain_id,
                }
            )
        },
        name="bridge-page-artifact",
    )

    plan.add_service(
        name="ictt-frontend",
        config=ServiceConfig(
            image=WEB_APPS_IMAGE,
            files={
                "/app/src/app/chains/definitions": Directory(
                    artifact_names=chain_cfg_artifacts,
                ),
                "/app/src/app/ictt/": Directory(
                    artifact_names=[page_artifact,constants_artifact]
                ),
            },
            ports={
                "frontend": PortSpec(
                    number=3000,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            }
        ),
    )

def get_chain_list(plan, l1_info): 
    return l1_info.keys()

def get_bridge_config_info(plan, l1_info, chain_config):
    token_cfgs = []
    src_chain_id = ""
    dest_chain_id = ""
    token_address = ""

    for chain in chain_config:
        if "erc20-bridge-config" not in chain:
            continue
        
        source_chain_name = chain["name"]
        src_chain_id = l1_info[source_chain_name]["NetworkdId"]
        token_address = l1_info[source_chain_name]["ERC20TokenAddress"]
        token_home_address = l1_info[source_chain_name]["TokenHomeAddress"] 
        source_chain_token_cfg = {
            "address": token_address,
            "name": "TOK",
            "symbol": "TOK",
            "chain_id": src_chain_id,
            "transferer": token_home_address,
            "mirrors": []
        }

        for dest_chain_name in chain["erc20-bridge-config"]["destinations"]:
            dest_chain_id = l1_info[dest_chain_name]["NetworkId"] 
            token_remote_address = l1_info[dest_chain_name]["TokenRemoteAddress"] 
            dest_chain_token_cfg = {
                "address": token_remote_address,
                "name": "TOK.e",
                "symbol": "TOK.e",
                "chain_id": dest_chain_id,
                "is_transferer": "true",
                "mirrors": [
                    {
                        "home": "true",
                        "address": token_address,
                        "transferer": token_home_address,
                        "chain_id": src_chain_id,
                    }
                ]
            }
            token_cfgs.append(dest_chain_token_cfg)

            source_chain_token_cfg["mirrors"].append({
                "address": token_remote_address,
                "transferer": token_remote_address,
                "chain_id": dest_chain_id,
            })
        token_cfgs.append(source_chain_token_cfg)

    return src_chain_id, dest_chain_id, token_address, token_cfgs




