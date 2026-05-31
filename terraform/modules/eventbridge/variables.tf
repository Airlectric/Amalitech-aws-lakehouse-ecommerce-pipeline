variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "raw_bucket_id" {
  description = "ID (name) of the raw S3 bucket to watch for Object Created events"
  type        = string
}

variable "router_lambda_arn" {
  description = "ARN of the pipeline-router Lambda function"
  type        = string
}

variable "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role"
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the SQS dead-letter queue for failed rule deliveries"
  type        = string
}
