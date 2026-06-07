variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lakehouse-dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}






variable "bucket_suffix" {
  description = "Suffix appended to all S3 bucket names (typically the AWS account ID)"
  type        = string
}

variable "alert_emails" {
  description = "List of email addresses to subscribe to the alerts SNS topic"
  type        = list(string)
  default     = []
}

variable "enable_crawler" {
  description = "When true, create Glue Crawlers to keep partition metadata current"
  type        = bool
  default     = false
}

variable "worker_count" {
  description = "Number of G.1X workers per Glue job"
  type        = number
  default     = 2
}

variable "glue_max_retries" {
  description = "Maximum automatic retries for Glue jobs"
  type        = number
  default     = 1
}

variable "glue_timeout_minutes" {
  description = "Timeout in minutes for each Glue job"
  type        = number
  default     = 60
}
