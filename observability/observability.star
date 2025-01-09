prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")
grafana = import_module("github.com/kurtosis-tech/grafana-package/main.star")

def launch_observability(plan, node_info):
    # only launch observability on first node
    # TODO: if needed launch a grafana instance for each node
    metrics_jobs = []
    node_name = node_info.keys()[0]
    metrics_jobs.append({ 
        "Name": "{0}-metrics".format(node_name), 
        "Endpoint": node_info[node_name]["rpc-url"].replace("http://", "", 1),
        "MetricsPath": "/ext/metrics",
        "Labels": {
            # "job": node_name,
            "job": "avalanchego",
        },
    })
       
    prometheus_url = prometheus.run(plan, metrics_jobs)

    # TODO: pass the dashboards in as a files artifact and not a locat
    grafana.run(plan, prometheus_url, "/dashboards")



