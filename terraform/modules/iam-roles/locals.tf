locals {
  account_id = data.aws_caller_identity.current.account_id

  # ── ARN conventions ─────────────────────────────────────────────────────────
  step_functions_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.environment}-lakehouse-pipeline"

  lambda_router_arn   = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-pipeline-router"
  lambda_archiver_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-file-archiver"

  # Referenced by ARN convention to avoid a circular module dependency.
  pipeline_dlq_arn = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.environment}-pipeline-dlq"

  # ── KMS action sets ──────────────────────────────────────────────────────────
  kms_decrypt = [
    "kms:Decrypt",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]

  kms_encrypt_decrypt = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
    "kms:DescribeKey",
  ]

  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "iam"
    Project     = "lakehouse-ecommerce"
  }
}
