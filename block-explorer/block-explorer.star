postgres = import_module("github.com/kurtosis-tech/postgres-package/main.star")

def launch_blockscout(
    plan,
    chain_name,
    chain_id,
    chain_rpc_url,
    chain_ws_url,
    maybe_codespace_name,
    chain_num
):
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
            image="ghcr.io/blockscout/smart-contract-verifier:latest",
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
            image="blockscout/blockscout:latest",
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
                "COIN": "ETH",
                "ETHEREUM_JSONRPC_VARIANT": "geth", # avalanche subnet evms are 1:1 with geth
                "ETHEREUM_JSONRPC_HTTP_URL": chain_rpc_url, 
                "ETHEREUM_JSONRPC_TRACE_URL": chain_rpc_url, 
                "ETHEREUM_JSONRPC_WS_URL": chain_ws_url, 
                "ETHEREUM_JSONRPC_HTTP_INSECURE": "true",
                "DATABASE_URL": postgres_url,
                "ECTO_USE_SSL": "false",
                "MICROSERVICE_SC_VERIFIER_ENABLED": "true",
                "MICROSERVICE_SC_VERIFIER_URL": verif_url, 
                "MICROSERVICE_SC_VERIFIER_TYPE": "sc_verifier",
                "INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER": "true",
                "API_V2_ENABLED": "true",
                "BLOCKSCOUT_PROTOCOL": "http",
                "SECRET_KEY_BASE": "56NtB48ear7+wMSf0IQuWDAAazhpb31qyc7GiyspBP2vh7t5zlCsF5QDv76chXeN", # whats this needed for?
            },
        )
    )
    plan.print(blockscout_service)

    blockscout_url = "http://{}:{}".format(blockscout_service.hostname, blockscout_service.ports["http"].number)

    # frontend
    frontend_port_num = 3000 + chain_num

    public_host = ""
    public_host_uri = ""
    next_public_app_port = 0
    if maybe_codespace_name != "":
        public_host = "{0}-{1}".format(maybe_codespace_name, frontend_port_num)
        public_host_uri = "https://{0}".format(public_host)
        next_public_app_port_num = 443 # codespace host is a proxy -
    else:
        public_host = "127.0.0.1"
        public_host_uri = "http://{0}:{1}".format(public_host, frontend_port_num)
        next_public_app_port_num = frontend_port_num

    blockscout_frontend = plan.add_service(
        name="blockscout-frontend-{0}".format(chain_name),
        config=ServiceConfig(
            image="ghcr.io/blockscout/frontend:latest",
            ports={
                "http": PortSpec(
                    number=frontend_port_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                    wait="30s",
                )
            },
            public_ports = {
                "http": PortSpec(
                    number=3000 + chain_num,
                    transport_protocol="TCP",
                    application_protocol="http",
                    wait="30s",
                )
            },
            env_vars={
                "PORT": str(frontend_port_num),
                ## Blockchain configuration.
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#blockchain-parameters
                "NEXT_PUBLIC_NETWORK_NAME": chain_name,
                "NEXT_PUBLIC_NETWORK_ID": str(chain_id),
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#transaction-interpretation
                "NEXT_PUBLIC_TRANSACTION_INTERPRETATION_PROVIDER": "blockscout",
                ## API configuration.
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#api-configuration
                "NEXT_PUBLIC_API_PROTOCOL": "http",
                "NEXT_PUBLIC_API_HOST": blockscout_service.ip_address + ":" + str(blockscout_service.ports["http"].number),
                "NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL": "ws",
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#app-configuration
                "NEXT_PUBLIC_APP_PROTOCOL": "http",
                "NEXT_PUBLIC_APP_HOST": public_host,
                "NEXT_PUBLIC_APP_PORT": str(next_public_app_port_num),
                "NEXT_PUBLIC_USE_NEXT_JS_PROXY": "true",
                ## Remove ads.
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#banner-ads
                "NEXT_PUBLIC_AD_BANNER_PROVIDER": "none",
                # https://github.com/blockscout/frontend/blob/main/docs/ENVS.md#text-ads
                "NEXT_PUBLIC_AD_TEXT_PROVIDER": "none",
                "NEXT_PUBLIC_IS_TESTNET": "true",
                "NEXT_PUBLIC_GAS_TRACKER_ENABLED": "true",
                "NEXT_PUBLIC_NETWORK_ICON": "https://raw.githubusercontent.com/ava-labs/avalanche-faucet/refs/heads/main/client/public/avax.webp"
            }
        ),
    )

    return public_host_uri