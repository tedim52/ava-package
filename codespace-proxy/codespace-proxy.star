
PROXY_PORT = 9649

def launch_node_proxy(plan, node_rpc_url):
    proxy_cfg_tmpl = read_file("./nginx.conf.tmpl")
    proxy_nginx_config = plan.render_templates(name="proxy-nginx-config", config={
        "nginx.conf":struct(
            template=proxy_cfg_tmpl,
            data={
                "Node1IpAddrAndPort": node_rpc_url,
            }
        )
    })

    plan.add_service(
        name="node-proxy",
        config=ServiceConfig(
            image="nginx:latest",
            ports={
                "proxy": PortSpec(number=PROXY_PORT, transport_protocol="TCP", application_protocol="HTTP")
            },
            public_ports={
                "proxy": PortSpec(number=PROXY_PORT, transport_protocol="TCP", application_protocol="HTTP")
            },
            files={
                "/etc/nginx/": proxy_nginx_config
            }
        )
    )

    return PROXY_PORT