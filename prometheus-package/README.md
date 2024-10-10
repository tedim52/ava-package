Prometheus Package
============
This is a [Kurtosis](https://github.com/kurtosis-tech/kurtosis/) package for starting a Prometheus server.

Run this package
----------------
If you have [Kurtosis installed][install-kurtosis], run:

```bash
kurtosis run github.com/kurtosis-tech/prometheus-package
```

If you don't have Kurtosis installed, [click here to run this package on the Kurtosis playground](https://gitpod.io/?autoStart=true&editor=code#https://github.com/kurtosis-tech/playground-gitpod).

To blow away the created [enclave][enclaves-reference], run `kurtosis clean -a`.

#### Configuration

You can configure this package using the JSON structure below. The default values for each parameter are shown.

NOTE: the `//` lines are not valid JSON; you will need to remove them!

```javascript
{
    "metrics_jobs": [
        {
            // name of metrics job
            "Name": "" , 

            // endpoint to scrape metrics from,eg. <services ip address>:<exposed metrics port>
            "Endpoint": "", 

            // labels to associate with scraped metrics (eg. { "service_type": "api" } )
            // optional
            "Labels": {}, 

            // http path to scrape metrics from
            // optional
            "MetricsPath": "/metrics", 

            // how frequently to scrape targets from this job
            // optional
            "ScrapeInterval": "15s"
        },
        { 
           // ...
        },
    ]
}
```

The arguments can then be passed in to `kurtosis run`.

For example:

```bash
kurtosis run github.com/kurtosis-tech/prometheus-package '{"metrics_jobs": [...]}'
```

You can also store the JSON args in a file, and use `--args-file` flag to slot them in:

```bash
kurtosis run github.com/kurtosis-tech/prometheus-package --args-file args.json
```

</details>

Use this package in your package
--------------------------------
Kurtosis packages can be composed inside other Kurtosis packages. To use this package in your package:

First, import this package by adding the following to the top of your Starlark file.
Then, call the this package's `run` function somewhere in your Starlark script:

```python
# For remote packages: 
prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star") 

def run(plan, args = {}):
    service_a = plan.add_service(name="sevice_a", config=ServiceConfig(
        ...
        ports = {
            "metrics": PortSpec(number=9090, transport_protocol="TCP", application_protocol="http")
        },
        ...
    ))

    service_a_metrics_job = { 
        "Name":"service_a", 
        "Endpoint":"http://{0}:{1}".format(service_a.ip_address, service_a.ports["metrics"].number),
        "Labels": { 
            "service_type": "backend" 
        }
    }

    # start a prometheus server that scrapes service_a's metrics and returns a prom url for querying those metrics
    prometheus_url = prometheus-package.run(plan, [service_a_metrics_job])
```

If you want to use a fork or specific version of this package in your own package, you can replace the dependencies in your `kurtosis.yml` file using the [replace](https://docs.kurtosis.com/concepts-reference/kurtosis-yml/#replace) primitive. 
Within your `kurtosis.yml` file:
```python
name: github.com/example-org/example-repo
replace:
    github.com/kurtosis-tech/prometheus-package: github.com/YOURUSER/THISREPO@YOURBRANCH
```

Develop on this package
-----------------------
1. [Install Kurtosis][install-kurtosis]
1. Clone this repo
1. For your dev loop, run `kurtosis clean -a && kurtosis run .` inside the repo directory


<!-------------------------------- LINKS ------------------------------->
[install-kurtosis]: https://docs.kurtosis.com/install
[enclaves-reference]: https://docs.kurtosis.com/concepts-reference/enclaves
