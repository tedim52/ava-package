TX_SPAM_PK = "bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"

def spam_transactions(
    plan,
    node_uri,
    chain_name,
):
    plan.add_service(
        name="tx-spammer-{0}".format(chain_name), 
        config=ServiceConfig(
            image="ethpandaops/tx-fuzz:master",
            cmd = [
                "spam",
                "--rpc={0}".format(node_uri),
                "--sk={0}".format(TX_SPAM_PK),
            ],
        )
    )

