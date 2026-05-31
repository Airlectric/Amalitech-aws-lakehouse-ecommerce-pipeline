resource "aws_sfn_state_machine" "lakehouse_pipeline" {
  name     = "${var.environment}-lakehouse-pipeline"
  role_arn = var.step_functions_role_arn

  definition = local.definition
  type       = "STANDARD"

  tracing_configuration {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-lakehouse-pipeline" })
}
