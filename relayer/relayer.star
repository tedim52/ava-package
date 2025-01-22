redis = import_module("github.com/kurtosis-tech/redis-package/main.star")

DEFAULT_RELAYER_IMAGE = "avaplatform/awm-relayer:v1.4.0"
ETNA_RELAYER_IMAGE = "avaplatform/icm-relayer:v2.0.0-fuji"
ACCOUNT_PRIVATE_KEY = "d28fb31486d7bd9f7fbe4c9087939ce765d4c3acf577756b1f9af9702956a063"
MESSAGE_CONTRACT_ADDRESS = "0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf"
MESSAGE_FORMAT = "teleporter"

def launch_relayer(plan, bootnode_url, chain_info, is_etna):
    redis_service = redis.run(plan)

    relayer_config_tmpl = read_file(src="./relayer-config.json.tmpl")
    plan.print(relayer_config_tmpl)
    relayer_config = plan.render_templates(
        name="relayer-config",
        config={
            "relayer-config.json": struct(
                template=relayer_config_tmpl,
                data={
                    "InfoAPIBaseURL": bootnode_url,
                    "PChainAPIBaseURL": bootnode_url,
                    "RedisURL": redis_service.url,
                    "SourceBlockchains": get_source_blockchains(chain_info),
                    "DestinationBlockchains": get_dest_blockchains(chain_info),
                }
            )
        }
    )

    entrypoint = []
    image = ""
    if is_etna == True:
        image = ETNA_RELAYER_IMAGE
        entrypoint=["/bin/sh", "-c", "/usr/bin/icm-relayer --config-file /config/relayer-config.json"]
    else:
        image = DEFAULT_RELAYER_IMAGE
        entrypoint=["/bin/sh", "-c", "/usr/bin/awm-relayer --config-file /config/relayer-config.json"]

    plan.add_service(
        name="relayer",
        config=ServiceConfig(
            image=image,
            entrypoint=entrypoint,
            ports={
                "api": PortSpec(number=8080, transport_protocol="TCP", application_protocol="HTTP"),
            },
            files={
                "/config": relayer_config
            },
        )
    )

def get_source_blockchains(chain_info):
    source_blockchains = []

    for chain_name, chain in chain_info.items():
        chain["MessageContractAddress"] = MESSAGE_CONTRACT_ADDRESS
        chain["MessageFormat"] = MESSAGE_FORMAT
        source_blockchains.append(chain)

    return source_blockchains

def get_dest_blockchains(chain_info):
    dest_blockchains = []

    for chain_name, chain in chain_info.items():
        chain["AccountPrivateKey"] = ACCOUNT_PRIVATE_KEY
        dest_blockchains.append(chain)

    return dest_blockchains

