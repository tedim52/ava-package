
FOUNDRY_IMAGE = "tedim52/avalabs-deployment-utils:latest"
FUNDED_ADDRESS = "0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC"
PRIVATE_KEY = "56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027"

def run(plan):
    token_home_address = deploy_token_remote(plan, "http://172.16.0.7:9650/ext/bc/2V7YAR8ppe7LpmJQaYSqru8VuzHcf6Wsnwdoy6PxBcdL8eondR/rpc", "TOK", "0x17ab05351fc94a1a67bf3f56ddbb941ae6c63e25", "0x6b14b55a2b76b8c759b555459bfbe17bab8719dbdb70a032c1b886b41bcf1b70", "0x5DB9A7629912EBF95876228C24A848de0bfB43A9")
    plan.print(token_home_address)

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



