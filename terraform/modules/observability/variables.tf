variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "glue_job_names" {
  description = "Map of Glue job names by dataset key (products, orders, order_items)"
  type        = map(string)
}

variable "lambda_function_names" {
  description = "Map of Lambda function names by role (router, archiver)"
  type        = map(string)
}

variable "step_functions_state_machine_arn" {
  description = "ARN of the lakehouse pipeline state machine"
  type        = string
}

variable "pipeline_dlq_arn" {
  description = "ARN of the pipeline dead-letter SQS queue"
  type        = string
}

variable "pipeline_dlq_name" {
  description = "Name of the pipeline dead-letter SQS queue"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw S3 bucket (for CloudTrail and dashboard)"
  type        = string
}

variable "dwh_bucket_name" {
  description = "Name of the DWH S3 bucket (for CloudTrail)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudTrail logs"
  type        = string
}

variable "alert_emails" {
  description = "List of email addresses to subscribe to the alerts SNS topic"
  type        = list(string)
  default     = []
}

variable "eventbridge_rule_name" {
  description = "Name of the EventBridge rule (for the dead-end invocations alarm)"
  type        = string
  default     = ""
}

variable "dataset_names" {
  description = "List of dataset names for per-dataset DQ rejection-rate alarms"
  type        = list(string)
  default     = ["products", "orders", "order_items"]
}

variable "dq_rejection_rate_threshold" {
  description = "RejectedRatePct threshold (%) above which the DQ alarm fires"
  type        = number
  default     = 20
}

variable "sla_breach_hours" {
  description = "Hours without a successful SFN execution before the SLA alarm fires"
  type        = number
  default     = 25
}
