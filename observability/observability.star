prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")
grafana = import_module("github.com/kurtosis-tech/grafana-package/main.star")

def launch_observability(plan, node_info):
    metrics_jobs = []
    for node_name, node_i in node_info.items():
        metrics_jobs.append({ 
            "Name": "{0}-metrics".format(node_name), 
            "Endpoint": node_i["rpc-url"].replace("http://", "", 1),
            "MetricsPath": "/ext/metrics",
            "Labels": {
                "job": node_name,
            },
        })

    # TODO: run node exporter prom plugin

    prometheus_url = prometheus.run(plan, metrics_jobs)

    # TODO: get these dashboards up and running on a git repo
    grafana.run(plan, prometheus_url, "/dashboards")



