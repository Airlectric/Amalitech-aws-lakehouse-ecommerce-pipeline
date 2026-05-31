variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "raw_bucket_arn" {
  description = "ARN of the raw (landing) S3 bucket"
  type        = string
}

variable "scripts_bucket_arn" {
  description = "ARN of the Glue scripts S3 bucket"
  type        = string
}

variable "dwh_bucket_arn" {
  description = "ARN of the DWH (Delta tables) S3 bucket"
  type        = string
}

variable "rejected_bucket_arn" {
  description = "ARN of the rejected records S3 bucket"
  type        = string
}

variable "archived_bucket_arn" {
  description = "ARN of the archived raw files S3 bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption"
  type        = string
}

variable "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic (used by Step Functions)"
  type        = string
  default     = null
}
