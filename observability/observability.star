prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")
grafana = import_module("github.com/kurtosis-tech/grafana-package/main.star")

def launch_observability(plan, node_info):
    metrics_jobs = []

    # only launch observability on first node
    # TODO: if needed launch a grafana instance for each node
    node_name = node_info.keys()[0]
    metrics_jobs.append({ 
        "Name": "{0}-metrics".format(node_name), 
        "Endpoint": node_info[node_name]["rpc-url"].replace("http://", "", 1),
        "MetricsPath": "/ext/metrics",
        "Labels": {
            "job": "avalanchego", # job name associated with node metrics in grafana dashboards
        },
    })

    node_exporter = plan.add_service(
        name="node-exporter",
        config=ServiceConfig(
            image="tedim52/node-exporter",
            cmd=["/bin/sh", "-c", "./node_exporter"],
            ports={
                "node-exporter": PortSpec(
                    number=9100,
                    transport_protocol="TCP",
                    application_protocol="http"
                )
            }
        )
    )

    metrics_jobs.append({ 
        "Name": "node-exporter", 
        "Endpoint": "{0}:{1}".format(node_exporter.ip_address, node_exporter.ports["node-exporter"].number),
        "Labels": {
            "job": "avalanchego-machine", # job name associated with machine metrics in grafana dashboards
        },
    })

    prometheus_url = prometheus.run(plan, metrics_jobs)

    # TODO: pass the dashboards in as a files artifact and not a locator
    grafana.run(plan, prometheus_url, "/dashboards")



