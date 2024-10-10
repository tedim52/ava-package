
def deploy_contracts(plan, subnet_uri):
    read_file
    teleporter_deployment_tools = plan.upload_files(name="teleporter-deployment-tools", src="./teleporter-code")

    teleporter_contract = plan.upload_files(name="teleporter-contract", src="./teleporter-contract.json")
    plan.run_sh(
        description="Construct keyless transaction for teleporter contract deployment",
        image="golang:1.22.2"
        run="cd /tmp/teleporter-code && go run main.go {0} {1} {}
        files={
            "/tmp/teleporter-code": teleporter_deployment_tools,
            "/tmp/teleporter-contract"
        },
        store=[
            StoreSpec(src="/tmp/teleporter-code/", name=""),
            StoreSpec(src="", name=""),
            StoreSpec(src="", name=""),
        ]
    )

    plan.