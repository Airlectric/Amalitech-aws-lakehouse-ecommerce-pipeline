variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "lambda_router_role_arn" {
  description = "ARN of the Lambda pipeline-router IAM role"
  type        = string
}

variable "lambda_archiver_role_arn" {
  description = "ARN of the Lambda file-archiver IAM role"
  type        = string
}

variable "archived_bucket_id" {
  description = "S3 bucket ID where the archiver writes processed raw files"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the archiver VPC config"
  type        = list(string)
}

variable "security_group_lambda_id" {
  description = "Security group ID attached to the archiver Lambda"
  type        = string
}

variable "eventbridge_rule_name" {
  description = "Name of the EventBridge rule that invokes the router (for the SQS queue policy)"
  type        = string
  default     = ""
}
