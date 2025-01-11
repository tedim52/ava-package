# FOUNDRY_IMAGE="ghcr.io/foundry-rs/foundry:latest"
# FOUNDRY_IMAGE="tedim52/foundry:latest"
FOUNDRY_IMAGE="tedim52/avalabs-deployment-utils:latest"
FOUNDRY_JQ_IMAGE="tedim52/foundry-jq:latest"

PRIVATE_KEY="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
FUNDED_ADDRESS="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
TELEPORTER_REGISTRY_VERSION="v1.0.0"
FOUNDRY_CONFIG_ARTIFACT_NAME="foundry-config"

def deploy_teleporter_registry(plan, chain_rpc_url, chain_name):
    deploy_registy_script = plan.upload_files(src="./deploy_registry.sh", name="deploy-registry-script-{0}".format(chain_name))
    deploy_result =plan.run_sh(
        description="Deploying Teleporter Registry contract to L1",
        name="teleporter-registry-deployer",
        run="/home/deploy_registry.sh --version {0} --rpc-url {1} --private-key {2} > /home/registry_address.txt".format(TELEPORTER_REGISTRY_VERSION, chain_rpc_url, PRIVATE_KEY),
        image=FOUNDRY_IMAGE,
        files = {
            "/home": deploy_registy_script,
        },
        store=[
            StoreSpec(name="registry-address-artifact", src="/home/registry_address.txt")
        ],
    )
    read_result = plan.run_sh(
        description="Reading Teleporter Registry address",
        name="teleporter-registry-address-reader",
        run="cat /home/registry_address.txt | tr -d '\n'",
        files={
            "/home": deploy_result.files_artifacts[0],
        }
    )
    teleporter_registry_address = read_result.output
    return teleporter_registry_address

def deploy_teleporter_messenger(plan, chain_rpc_url, chain_name):
    deploy_teleporter_script = plan.upload_files(src="./deploy_teleporter.sh", name="deploy-teleporter-script-{0}".format(chain_name))
    deploy_result =plan.run_sh(
        description="Deploying Teleporter Messenger contract to L1",
        name="teleporter-messenger-deployer",
        run="/home/deploy_teleporter.sh --version {0} --rpc-url {1} --private-key {2} > /home/messenger_address.txt".format(TELEPORTER_REGISTRY_VERSION, chain_rpc_url, PRIVATE_KEY),
        image=FOUNDRY_IMAGE,
        files = {
            "/home": deploy_teleporter_script,
        },
        store=[
            StoreSpec(name="messenger-address-artifact", src="/home/messenger_address.txt")
        ],
    )
    read_result = plan.run_sh(
        description="Reading Teleporter Messenger address",
        name="teleporter-messenger-address-reader",
        run="cat /home/messenger_address.txt | tr -d '\n'",
        files={
            "/home": deploy_result.files_artifacts[0],
        }
    )
    teleporter_messenger = read_result.output
    return teleporter_messenger

# TODO: enable parameterizing token name
def deploy_erc20_token(plan, chain_rpc_url, token_name): 
    result = plan.run_sh(
        description="Deploying ERC20 Token contract to L1",
        name="erc20-token-deployer",
        run="forge create contracts/interchain-token-transfer/MyToken.sol:TOK --rpc-url {0} --private-key {1} | grep -oP '(?<=Deployed to: )0x[0-9a-fA-F]+$' | tr -d '\n'".format(chain_rpc_url, PRIVATE_KEY),
        image=FOUNDRY_IMAGE,
    )
    erc20_token_address = result.output
    return erc20_token_address

def deploy_token_home(plan, chain_rpc_url, token_name, teleporter_registry_address, erc20_token_address): 
    plan.print("deploy token home cmd: forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenHome/ERC20TokenHome.sol:ERC20TokenHome --constructor-args {2} {3} {4} 18".format(chain_rpc_url, PRIVATE_KEY, teleporter_registry_address, FUNDED_ADDRESS, erc20_token_address))
    result = plan.run_sh(
        description="Deploying TokenHome contract to L1",
        name="token-home-deployer",
        run="forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenHome/ERC20TokenHome.sol:ERC20TokenHome --constructor-args {2} {3} {4} 18 | grep -oP '(?<=Deployed to: )0x[0-9a-fA-F]+$' | tr -d '\n'".format(chain_rpc_url, PRIVATE_KEY, teleporter_registry_address, FUNDED_ADDRESS, erc20_token_address),
        image=FOUNDRY_IMAGE,
    )
    token_home_contract_address = result.output
    plan.run_sh(
        description="Approving TokenHome to transfer tokens on ERC20 behalf",
        name="token-home-approver",
        run="cast send --rpc-url {0} --private-key {1} {2} \"approve(address, uint256)\" {3} 2000000000000000000000".format(chain_rpc_url, PRIVATE_KEY, erc20_token_address, token_home_contract_address),
        image=FOUNDRY_IMAGE,
    )
    return token_home_contract_address

def deploy_token_remote(plan, chain_rpc_url, token_name, dest_teleporter_registry_address, source_blockchain_id_hex, source_token_home_address): 
    result = plan.run_sh(
        description="Deploying TokenRemote contract to destination L1",
        name="token-remote-deployer",
        run="forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenRemote/ERC20TokenRemote.sol:ERC20TokenRemote --constructor-args \"({2},{3},{4},{5},18)\" \"TOK\" \"TOK\" 18 | grep -oP '(?<=Deployed to: )0x[0-9a-fA-F]+$' | tr -d '\n'".format(
            chain_rpc_url,
            PRIVATE_KEY,
            dest_teleporter_registry_address,
            FUNDED_ADDRESS,
            source_blockchain_id_hex,
            source_token_home_address),
        image=FOUNDRY_IMAGE,
    )
    token_remote_address = result.output

    # run register with home step
    plan.run_sh(
        description="Registering TokenRemote {0} with TokenHome {1}".format(token_remote_address, source_token_home_address),
        name="register-token-remote-deployer",
        run="cast send --rpc-url {0} --private-key {1} {2} \"registerWithHome((address, uint256))\" \"(0x0000000000000000000000000000000000000000, 0)\"".format(chain_rpc_url, PRIVATE_KEY, token_remote_address),
        image=FOUNDRY_IMAGE,
    )
    return token_remote_address

def get_tx_nonce(plan, service_name, blockchain_id, address):
    response = plan.request(
        service_name=service_name,
        recipe=PostHttpRequestRecipe(
            port_id="rpc",
            endpoint="/ext/bc/{0}/rpc".format(blockchain_id),
            content_type="application/json",
            body="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"" + address + "\", \"latest\"],\"id\":1}",
            extract = {
                "nonce" : ".result",
            },
        ),
        acceptable_codes=[200],
        description="Get current nonce for {0}".format(address)
    )
    decimal_nonce_output = plan.run_sh(
        run="printf \"%d\" {0}".format(response["extract.nonce"]),
        description="Convert hex {0} nonce to decimal nonce".format(response["extract.nonce"])
    )
    return decimal_nonce_output.output


