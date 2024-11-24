
def spam_transactions(
    plan,
    node_uri,
    private_key,
    chain_name,
):
    plan.add_service(
        name="tx-spammer-{0}".format(chain_name), 
        config=ServiceConfig(
            image="ethpandaops/tx-fuzz:master",
            cmd = [
                "spam",
                "--rpc={0}".format(node_uri),
                "--sk={0}".format(private_key),
            ],
        )
    )

