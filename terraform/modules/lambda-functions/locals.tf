locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "lambda-functions"
    Project     = "lakehouse-ecommerce"
  }

  # Constructed by convention to avoid a circular dependency with the
  # step-functions module.
  step_functions_arn = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.environment}-lakehouse-pipeline"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
