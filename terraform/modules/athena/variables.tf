variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "athena_results_bucket_id" {
  description = "ID (name) of the S3 bucket for Athena query results"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Athena query results"
  type        = string
}
