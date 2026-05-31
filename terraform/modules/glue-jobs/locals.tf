locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "glue-jobs"
    Project     = "lakehouse-ecommerce"
  }

  # S3 key prefix under which all scripts are stored.
  script_key = "scripts/${var.environment}"

  # Per-dataset job arguments shared across all three jobs.
  common_job_args = {
    "--datalake-formats"                 = "delta"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--extra-py-files"                   = "s3://${var.scripts_bucket_id}/${local.script_key}/common.zip"
  }
}
