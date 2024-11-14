postgres = import_module("github.com/kurtosis-tech/postgres-package/main.star")

def launch_blockscout(plan, args):
    postgres_service = postgres.run(plan, args)

    # configure backend
    # start backend
    plan.add_service(
        name="",
        config=ServiceConfig(

        )
    )

    # start frontend
    plan.add_service(
        name="",
        config=ServiceConfig(

        ))









