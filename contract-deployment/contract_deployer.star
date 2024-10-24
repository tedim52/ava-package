FOUNDRY_IMAGE="ghcr.io/foundry-rs/foundry:latest"
FOUNDRY_IMAGE="tedim52/foundry"
FOUNDRY_JQ_IMAGE="tedim52/foundry-jq:latest"

PRIVATE_KEY="56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"
FUNDED_ADDRESS="0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
TELEPORTER_REGISTRY_VERSION="v1.0.0"
AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME="avalanche-starter-kit"

def upload_avalanche_starter_kit(plan):
    # uploads all the solidity contracts needed to be deployed into a files artifact in the enclave
    # this should be run before any of the functions in this module
    plan.upload_files(src="./avalanche-starter-kit", name=AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME)
    # plan.upload_files(src="./avalanche-interchain-token-transfer", name=AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME)

def deploy_teleporter_registry(plan, chain_rpc_url):
    deploy_registy_script = plan.upload_files(src="./deploy_registry.sh", name="deploy-registry-script")
    result=plan.run_sh(
        description="Deploying Teleporter Registry contract to L1",
        name="teleporter-registry-deployer",
        run="./home/deploy_registry.sh --version {0} --rpc-url {1} --private-key {2}".format(TELEPORTER_REGISTRY_VERSION, chain_rpc_url, PRIVATE_KEY),
        image=FOUNDRY_IMAGE,
        files={
            "/home": deploy_registy_script,
        },
    )
    teleporter_registry_address = result.output
    return teleporter_registry_address

# TODO: enable parameterizing token name
def deploy_erc20_token(plan, chain_rpc_url, token_name): 
    avalanche_starter_kit = plan.get_files_artifact(src=AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME)
    result = plan.run_sh(
        description="Deploying ERC20 Token contract to L1",
        name="erc20-token-deployer",
        run="cd /home/avalanche-starter-kit && forge create --rpc-url {0} --private-key {1} contracts/interchain-token-transfer/MyToken.sol:TOK".format(chain_rpc_url, PRIVATE_KEY),
        image=FOUNDRY_IMAGE,
        files={
            "/home": avalanche_starter_kit,
        },
    )
    # parse output
    erc20_token_address = result.output

    #TODO: run validation step? check if funded address has a balance using cast call
    return erc20_token_address

def deploy_token_home(plan, chain_rpc_url, token_name, teleporter_registry_address, erc20_token_address): 
    avalanche_starter_kit = plan.get_files_artifact(src=AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME)
    result = plan.run_sh(
        description="Deploying TokenHome contract to L1",
        name="token-home-deployer",
        run="cd /home/avalanche-starter-kit && forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenHome/ERC20TokenHome.sol:ERC20TokenHome --constructor-args {2} {3} {4} 18".format(chain_rpc_url, PRIVATE_KEY, teleporter_registry_address, erc20_token_address),
        image=FOUNDRY_IMAGE,
        files={
            "/home": avalanche_starter_kit,
        },
    )
    token_home_contract = result.output

    # run approve step
    return teleporter_registry_address

def deploy_token_remote(plan, chain_rpc_url, token_name, teleporter_registry_address, erc20_token_address): 
    avalanche_starter_kit = plan.get_files_artifact(src=AVALANCHE_STARTER_KIT_FILES_ARTIFACT_NAME)
    result = plan.run_sh(
        description="Deploying TokenRemote contract to L1",
        name="token-remote-deployer",
        run="cd /home/avalanche-starter-kit && forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenHome/ERC20TokenHome.sol:ERC20TokenHome --constructor-args {2} {3} {4} 18".format(chain_rpc_url, PRIVATE_KEY, teleporter_registry_address, erc20_token_address),
        image=FOUNDRY_IMAGE,
        files={
            "/home": avalanche_starter_kit,
        },
    )
    token_remote_address = result.output

    # run register with home step
    result = plan.run_sh(
        description="Registering TokenRemote with TokenHome {0}".format(),
        name="register-token-remote-deployer",
        run="cd /home/avalanche-starter-kit && forge create --rpc-url {0} --private-key {1} lib/avalanche-interchain-token-transfer/contracts/src/TokenHome/ERC20TokenHome.sol:ERC20TokenHome --constructor-args {2} {3} {4} 18".format(chain_rpc_url, PRIVATE_KEY, teleporter_registry_address, erc20_token_address),
        image=FOUNDRY_IMAGE,
        files={
            "/home": avalanche_starter_kit,
        },
    )
    return token_remote_address




