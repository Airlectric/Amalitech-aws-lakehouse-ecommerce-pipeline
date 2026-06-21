variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "scripts_bucket_id" {
  description = "S3 bucket ID for Glue scripts, common zip and temp files"
  type        = string
}

variable "raw_bucket_id" {
  description = "Raw (landing) S3 bucket ID passed to each job at runtime"
  type        = string
}

variable "dwh_bucket_id" {
  description = "DWH (Delta tables) S3 bucket ID"
  type        = string
}

variable "rejected_bucket_id" {
  description = "Rejected records S3 bucket ID"
  type        = string
}

variable "glue_etl_role_arn" {
  description = "ARN of the shared Glue ETL IAM role"
  type        = string
}




variable "worker_count" {
  description = "Number of G.1X workers per Glue job"
  type        = number
  default     = 2
}

variable "max_retries" {
  description = "Maximum automatic retries for Glue jobs"
  type        = number
  default     = 1
}

variable "timeout_minutes" {
  description = "Timeout in minutes for each Glue job"
  type        = number
  default     = 60
}

variable "maintenance_schedule" {
  description = "EventBridge Scheduler cron expression for the daily Delta maintenance run"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "vacuum_retain_hours" {
  description = "Minimum hours to retain Delta Lake file versions before VACUUM removes them (must be >= 168)"
  type        = number
  default     = 168
}
