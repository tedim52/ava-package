WEB_APPS_IMAGE = "tedim52/avalanche-web-apps:test"

def launch_bridge_frontend(plan, l1_info, chain_config):
    src_blockchain_id, dest_blockchain_id, token_address, chain_cfgs, token_cfgs = get_bridge_config_info(plan, l1_info, chain_config)

    chain_cfg_tmpl = read_file(src="./chains.json.tmpl")
    chain_cfg_artifact = plan.render_templates(
            config={
                "chains.json": struct(
                    template=chain_cfg_tmpl,
                    data={
                        "Blockchains": chain_cfgs,
                    }
                )
            },
            name="bridge-chain-config-artifact",
    )

    tokens_tmpl = read_file(src="./tokens.json.tmpl")
    tokens_artifact = plan.render_templates(
        config={
            "tokens.json": struct(
                template=tokens_tmpl,
                data={
                    "Tokens": token_cfgs,
                }
            )
        },
        name="bridge-tokens-artifact"
    )
    
    page_tmpl = read_file(src="./page-config.json.tmpl")
    page_artifact = plan.render_templates(
        config={
            "page-config.json": struct(
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
                "/app/data/": Directory(
                    artifact_names=[chain_cfg_artifact, page_artifact, tokens_artifact],
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

def get_bridge_config_info(plan, l1_info, chain_config):
    chain_cfgs = []
    token_cfgs = []
    src_chain_id = ""
    dest_chain_id = ""
    token_address = ""

    for chain in chain_config:
        source_chain_name = chain["name"]
        rpc_url = l1_info[source_chain_name]["CodespaceRPCEndpointBaseURL"] if "CodespaceRPCEndpointBaseURL" in l1_info[source_chain_name] else l1_info[source_chain_name]["PublicRPCEndpointBaseURL"]
        chain_cfgs.append({
            "NETWORK_ID": l1_info[source_chain_name]["NetworkId"],
            "BLOCKCHAIN_NAME": source_chain_name,
            "NETWORK_NAME": source_chain_name,
            "RPC_URL": rpc_url,
            "TELEPORTER_REGISTRY_ADDRESS": l1_info[source_chain_name]["TeleporterRegistryAddress"],
        })
        if "erc20-bridge-config" not in chain:
            continue
        
        src_chain_id = l1_info[source_chain_name]["NetworkId"]
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

    return src_chain_id, dest_chain_id, token_address, chain_cfgs, token_cfgs




