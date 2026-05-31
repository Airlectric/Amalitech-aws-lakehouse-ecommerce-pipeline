variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "step_functions_role_arn" {
  description = "ARN of the Step Functions IAM role"
  type        = string
}

variable "products_etl_job_name" {
  description = "Name of the Products ETL Glue job"
  type        = string
}

variable "orders_etl_job_name" {
  description = "Name of the Orders ETL Glue job"
  type        = string
}

variable "order_items_etl_job_name" {
  description = "Name of the Order Items ETL Glue job"
  type        = string
}

variable "archiver_lambda_arn" {
  description = "ARN of the file-archiver Lambda function"
  type        = string
}

variable "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic for pipeline failure notifications"
  type        = string
  default     = null
}

variable "dwh_bucket_id" {
  description = "DWH S3 bucket ID (used to build --dwh_path argument)"
  type        = string
}

variable "rejected_bucket_id" {
  description = "Rejected records S3 bucket ID (used to build --rejected_path argument)"
  type        = string
}
