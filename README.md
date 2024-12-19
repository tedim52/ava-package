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

You can find other configurations under the `config` folder.

To remove the created [enclave][enclaves-reference], run `kurtosis enclave rm avalanche -f`.

## 🚀 Codespace

Create a new Codespace from this repository using the button below. The default settings for the Codespace will work just fine.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=master&repo=864218549&skip_quickstart=true&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json)

Once the codespace is set up, run `chmod 777 ./scripts/setup-codespace.sh` followed by `./scripts/setup-codespace.sh` This will simply check that Docker is running and install Kurtosis. Then you will be able to run Kurtosis commands.

#### Configuration

<details>
    <summary>Click to see configuration</summary>

You can configure this package using the JSON structure below. The default values for each parameter are shown.

// NOTE and TODO: flesh out the configurable params and document available option

```javascript
{
    "base-network-id": "1337",
    // add more dicts to spin up more L1s
    "chain-configs": [
        {
            "name": "myblockchain",
            "vm": "subnetevm",
            "network-id": 555555,
            "enable-teleporter": true,
            "erc20-bridge-config": {
                "token-name": "TOK",
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
    "num-nodes": 3,
    "node-cfg": {
        "network-id": "1337",
        "staking-enabled": false,
        "health-check-frequency": "5s"
    }
}
```

</details>

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


<!-------------------------------- LINKS ------------------------------->
[install-kurtosis]: https://docs.kurtosis.com/install
[enclaves-reference]: https://docs.kurtosis.com/concepts-reference/enclaves