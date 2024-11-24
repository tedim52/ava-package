postgres = import_module("github.com/kurtosis-tech/postgres-package/main.star")
blockscout = import_module("github.com/tedim52/kurtosis-blockscout/main.star")

def launch_blockscout(
    plan,
    chain_name,
    chain_id,
    chain_rpc_url,
    chain_ws_url,
):
    # blockscout.run(plan, {
        # "chain_name": chain_name,
        # "chain_id": chain_id,
        # "chain_rpc_url": chain_rpc_url,
        # "chain_ws"url": chain_ws_url,
    # })
    postgres_output = postgres.run(
        plan,
        service_name="blockscout-postgres-{0}".format(chain_name),
        database="blockscout",
    )
    postgres_url = "{protocol}://{user}:{password}@{hostname}:{port}/{database}".format(
        protocol="postgresql",
        user=postgres_output.user,
        password=postgres_output.password,
        hostname=postgres_output.service.hostname,
        port=postgres_output.port.number,
        database=postgres_output.database,
    )
    
    verif_service = plan.add_service(
        name="blockscout-verif-{0}".format(chain_name),
        config=ServiceConfig(
            image="ghcr.io/blockscout/smart-contract-verifier:v1.9.0",
            ports={
                "http": PortSpec(
                    number=8050,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            env_vars={
                "SMART_CONTRACT_VERIFIER__SERVER__HTTP__ADDR": "0.0.0.0:8050",
            },
        )
    )

    verif_url = "http://{}:{}/".format(verif_service.hostname, verif_service.ports["http"].number)

    blockscout_service = plan.add_service(
        name="blockscout-{0}".format(chain_name), 
        config=ServiceConfig(
            # image="blockscout/blockscout:6.9.0",
            image="blockscout/blockscout:6.8.0",
            ports={
                "http": PortSpec(
                    number=4000,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            cmd=[
                "/bin/sh",
                "-c",
                'bin/blockscout eval "Elixir.Explorer.ReleaseTasks.create_and_migrate()" && bin/blockscout start',
            ],
            env_vars={
                "PORT": "4000",
                "NETWORK": chain_name, 
                "SUBNETWORK": chain_name,
                "CHAIN_ID": str(chain_id),
                # "CHAIN_TYPE": "ethereum",
                "COIN": "ETH",
                "ETHEREUM_JSONRPC_VARIANT": "geth", # avalanche subnet evms are 1:1 with geth
                "ETHEREUM_JSONRPC_HTTP_URL": chain_rpc_url, 
                "ETHEREUM_JSONRPC_TRACE_URL": chain_rpc_url, # TODO: whats the difference between http url
                "ETHEREUM_JSONRPC_WS_URL": chain_ws_url, 
                "ETHEREUM_JSONRPC_HTTP_INSECURE": "true",
                "DATABASE_URL": postgres_url,
                "ECTO_USE_SSL": "false",
                "MICROSERVICE_SC_VERIFIER_ENABLED": "true",
                "MICROSERVICE_SC_VERIFIER_URL": verif_url, # what does the verifier do?
                "MICROSERVICE_SC_VERIFIER_TYPE": "sc_verifier",
                "INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER": "true",
                "API_V2_ENABLED": "true",
                "BLOCKSCOUT_PROTOCOL": "http",
                "SECRET_KEY_BASE": "56NtB48ear7+wMSf0IQuWDAAazhpb31qyc7GiyspBP2vh7t5zlCsF5QDv76chXeN", # whats this needed for?
            },
        )
    )
    plan.print(blockscout_service)
    plan.exec(
        description="""
        Allow 60s for blockscout to start indexing,
        otherwise bs/Stats crashes because it expects to find content on DB
        """,
        service_name="blockscout-{0}".format(chain_name),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "sleep 60"],
        ),
    )

    blockscout_url = "http://{}:{}".format(blockscout_service.hostname, blockscout_service.ports["http"].number)

    # stats
    # stats_postgres_output = postgres.run(
    #     plan,
    #     service_name="blockscout-stats-postgres-{0}".format(chain_name),
    #     database="stats",
    # )
    # stats = plan.add_service(
    #     name="blockscout-stats-{0}".format(chain_name),
    #     config=ServiceConfig(
    #         image="ghcr.io/blockscout/stats:v2.1.1",
    #         ports={
    #             "stats": PortSpec(
    #                 number=8050, 
    #                 application_protocol="http", 
    #                 wait="30s"
    #             ),
    #         },
    #         env_vars={
    #             "STATS__DB_URL": stats_postgres_output.url, 
    #             "STATS__BLOCKSCOUT_DB_URL": postgres_url,
    #             "STATS__CREATE_DATABASE": "false",
    #             "STATS__RUN_MIGRATIONS": "true",
    #             "STATS__SERVER__HTTP__CORS__ENABLED": "false",
    #         },
    #     ),
    # )

    # # visualizer
    # visualizer = plan.add_service(
    #     name="blockscout-visualizer-{0}".format(chain_name),
    #     config=ServiceConfig(
    #         image="ghcr.io/blockscout/visualizer:v0.2.1",
    #         ports={
    #             "http": PortSpec(
    #                 number=8050, 
    #                 application_protocol="http"
    #             ),
    #         },
    #     ),
    # )

    # # frontend
    # blockscout_frontend = plan.add_service(
    #     name="blockscout-frontend-{0}".format(chain_name),
    #     config=ServiceConfig(
    #         image="ghcr.io/blockscout/frontend:v1.35.0",
    #         ports={
    #             "http": PortSpec(
    #                 number=8000,
    #                 transport_protocol="TCP",
    #                 application_protocol="http",
    #                 wait="30s",
    #             )
    #         },
    #         env_vars={
    #             "PORT": str(8000),
    #             ## Blockchain configuration.
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#blockchain-parameters
    #             "NEXT_PUBLIC_NETWORK_NAME": chain_name,
    #             "NEXT_PUBLIC_NETWORK_ID": str(chain_id),
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#rollup-chain
    #             # "NEXT_PUBLIC_ROLLUP_TYPE": "zkEvm",
    #             # "NEXT_PUBLIC_ROLLUP_L1_BASE_URL": l1_explorer,
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#transaction-interpretation
    #             "NEXT_PUBLIC_TRANSACTION_INTERPRETATION_PROVIDER": "blockscout",
    #             ## API configuration.
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#api-configuration
    #             "NEXT_PUBLIC_API_PROTOCOL": "http",
    #             "NEXT_PUBLIC_API_HOST": blockscout_service.ip_address,
    #             "NEXT_PUBLIC_API_PORT": str(blockscout_service.ports["http"].number),
    #             "NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL": "ws",
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#blockchain-statistics
    #             # "NEXT_PUBLIC_STATS_API_HOST": "http://{}:{}".format(
    #             #     stats.ip_address, stats.ports["stats"].number
    #             # ),
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#solidity-to-uml-diagrams
    #             "NEXT_PUBLIC_VISUALIZE_API_HOST": "http://{}:{}".format(
    #                 visualizer.ip_address, visualizer.ports["http"].number
    #             ),
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#app-configuration
    #             "NEXT_PUBLIC_APP_PROTOCOL": "http",
    #             "NEXT_PUBLIC_APP_HOST": "127.0.0.1",
    #             "NEXT_PUBLIC_APP_PORT": str(8000),
    #             "NEXT_PUBLIC_USE_NEXT_JS_PROXY": "true",
    #             ## Remove ads.
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#banner-ads
    #             "NEXT_PUBLIC_AD_BANNER_PROVIDER": "none",
    #             # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#text-ads
    #             "NEXT_PUBLIC_AD_TEXT_PROVIDER": "none",
    #         }
    #     ),
    # )

    return blockscout_url