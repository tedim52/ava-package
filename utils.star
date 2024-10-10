# reads the given file in service without the new line
def read_file_from_service(plan, service_name, filename):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cat {}".format(filename)]
        )
    )
    return output["output"]

def append_contents_to_file(plan, service_name, filename, content):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "echo -n \"{0}\" >> {1}".format(content, filename)]
        ),
        description="Appending {0} to '{1}' in {2}".format(content, filename, service_name)
    )
    return output["output"]

def write_contents_to_file(plan, service_name, filename, content):
    output = plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "echo \"{0}\" > {1}".format(content, filename)]
        )
    )
    return output["output"]
 