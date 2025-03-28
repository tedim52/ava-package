🔺 Avalanche Package
============
This is a [Kurtosis](https://github.com/kurtosis-tech/kurtosis/) package for spinning up a local configurable Avalanche network. 

Run this package
----------------
If you have [Kurtosis installed][install-kurtosis], clone this repo locally and run: 

```bash
kurtosis run . --enclave avalanche --args-file configs/one-chain.json
```

Once this repo is public users will also be able to run `kurtosis run github.com/ava-labs/avalanche-package` so they don't have to clone the repo.

You can find other configurations under the `configs/` folder. For example, if you'd like to try out the HyperSDK's starter vm, [`morpheusvm`](https://github.com/ava-labs/hypersdk/tree/main/examples/morpheusvm), run the `hypersdk.json` config.

To remove the created [enclave][enclaves-reference], run `kurtosis enclave rm avalanche -f`.

## 🚀 Codespace

Create a new Codespace from this repository using the button below. The default settings for the Codespace will work just fine.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=master&repo=864218549&skip_quickstart=true&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json)

Once the codespace is set up, run `chmod 777 ./scripts/setup-codespace.sh` followed by `./scripts/setup-codespace.sh` This will simply check that Docker is running and install Kurtosis. Then you will be able to run Kurtosis commands. Make sure to add the `codespace` key to configs with value being whatever `echo $CODESPACE_NAME` is, when running in codespace - see `configs/one-chain-codespace.json` as an example.

#### Configuration

You can configure this package using the JSON structure below. The default values for each parameter are shown.

```javascript
{
    // add more dicts to spin up more L1s
    "chain-configs": [
        {
            // the name of the blockchain you want to have
            "name": "myblockchain",

            // the vm you want to use to start the chain
            // currently the support options are subnetevm and morpheusvm
            // the default is subnetevm
            "vm": "subnetevm",

            // the network id for you chain
            "network-id": 555555,

            // whether or not you want to deploy teleporter contracts to your chain, defaults to true
            "enable-teleporter": true,

            // config to deploy an erc20 token bridge between to chains
            "erc20-bridge-config": {
                // name of token you want to enable bridging for, by default every subnetevm chain spun up by the package automatically deploys a token contract with the name TOK
                "token-name": "TOK",

                // the chain you want to enable bridging to
                // must be the name of another chain within this config file
                "destinations": ["mysecondblockchain"]
            }
        },
        {
            "name": "mysecondblockchain",
            "vm": "subnetevm",
            "network-id": 666666,
            "enable-teleporter": true
        }
    ],
    // number of nodes to start on the network
    "num-nodes": 3,

    "node-cfg": {
        // network id that nodes use to know where to connect, by default this is 1337 - which indicates a local avalanche network, options available are:
        // 1337 - local network (default)
        // fuji - connects fuji test network. note: connecting to fuji only works with one local node
        "network-id": "1337",
        "staking-enabled": false,
        "health-check-frequency": "5s"
    },
    
    // if you are running inside a codespace, provide this configuration with the value of `echo $CODESPACE_NAME`. 
    // this is needed to make sure that networking for additional services like the blockscout explorer are proxied to the codepsace correctly
    "codespace-name": "verbose-couscous-q45vq44g552657q",
    
    // a list of additional infrastructure services you can have the package spin up in the encalve
    "additional-services": {
        // starts prometheus + grafana instance connected to one node on the network
        // provides dashboards for monitoring the Avalanche node - including metrics on all primary network and configured chains, resource usage, etc
        "observability": true,

        // creates a tx spammer that spams transactions - note this only works for a subnetevm chain
        // one spammer is created for each subnetevm chain spun up in the package
        "tx-spammer": true,

        // spins up the interchain token transfer frontend, a UI that allows you to bridge ERC 20 tokens from one chain to another
        // note this only works for configs that deploy an erc20 token bridge and have at minimum to chains
        "ictt-frontend": true,

        // spins up a faucet configured for every chain spun up in the package
        "faucet": true,


        // spins up a blockscout explorer for each chain
        "block-explorer": true
    },

    // cpu arch of machine this package runs on 
    // this is only required when spinning up non-subnetevm chains(eg. morpheusvm), defaults to arm64
    "cpu-arch": "arm64",

    // if running subnetevm l1s, this is the version of subnet evm that will be used
    // default: 0.6.12
    "subnet-evm-version": "0.6.12"
}
```

Use this package in your package
--------------------------------
Kurtosis packages can be composed inside other Kurtosis packages. To use this package in your package:

First, import this package by adding the following to the top of your Starlark file:

```python
# For remote packages: 
avalanche = import_module("github.com/tedim52/ava-package/main.star") 

# For local packages:
avalanche = import_module(".src/main.star")
```

Develop on this package
-----------------------
1. [Install Kurtosis][install-kurtosis]
1. Clone this repo
1. For your dev loop, run `kurtosis clean -a && kurtosis run .` inside the repo directory

Package breakdown
-----------------------
A short breakdown of each directory for those who want are understand more about how this package is created or contribute.

- `main.star`
    -  Main entrypoint that contains the high level logic, structure, and arg configuration for the package. 
    - If you want to a high level view of the steps this package takes, start here.
- `builder/`
    - A simple docker container that contains code necessary to configure avalanche networks.
    - Contains `genesis-generator-code` thats used to configure primary network, configs for nodes, etc.
    - Contains `subnet-creator-code` thats used to create and configure local avalanche l1s. Performs all steps needed to create a POA avalanche l1 including creating subnet, blockchain, converting to l1, initializing validator manager contracts and set.
    - This builder service sticks around for entirety of package creation - downstream starlark logic runs commands on the builder that runs golang code mentioned above.
    - If you are looking for the avalanche code thats used to configure the networks, start here.
- `node_launcher.star`
    - Contains starlark node configuration - data produced by the `builder` is mounted onto the nodes and then used to configure them. 
    - Contains logic for how nodes are configured to track new l1s configured by the package.
- `l1/`
    - Contains starlark logic for configuring l1s. These steps execute commands on the `builder` container to start the l1 in three stages - `create`, `convert`, `initvalidadtorset`
- `relayer/`
    - Config to start the ICM relayer service used for relaying messages between avalanche l1s - this is used for the erc20 token bridge that can be spun up in this package.
- `faucet/`
    - Starts avalanche faucet service
- `block-explorer/`
    - Starts blockscout explorer
- `observablity/`
    - Configures prom and grafana
- `bridge-frontend/`
    - Starts interchain token transfer frontend

Dependencies
-----------------------
Curious about what docker images and other kurtosis packages this package depends on? 

Run any `kurtosis run .` command with `--dependencies` appended (e.g. `kurtosis run . --args-file configs/two-chains-with-bridge.json --dependencies`) to get a list of dependencies.

<!-------------------------------- LINKS ------------------------------->
[install-kurtosis]: https://docs.kurtosis.com/install
[enclaves-reference]: https://docs.kurtosis.com/concepts-reference/enclaves