
def spam_transactions(
    plan,
    node_uri,
    private_key,
    chain_count,
):
    plan.add_service(
        name="tx-spammer-{0}".format(chain_count), 
        config=ServiceConfig(
            image="ethpandaops/tx-fuzz:master",
            cmd = [
                "spam",
                "--rpc={}".format(node_uri),
                "--sk={0}".format(private_key),
            ],
        )
    )

