resource "aws_athena_workgroup" "analytics" {
  name        = "${var.environment}-analytics"
  description = "Lakehouse analytics workgroup – enforces SSE-KMS on all query results"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.athena_results_bucket_id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-analytics" })
}
