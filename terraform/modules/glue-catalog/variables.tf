variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "dwh_bucket_id" {
  description = "ID (name) of the DWH S3 bucket where Delta tables are stored"
  type        = string
}

variable "enable_crawler" {
  description = "When true, create a Glue Crawler for each table to keep partition metadata current"
  type        = bool
  default     = false
}

variable "glue_etl_role_arn" {
  description = "ARN of the Glue ETL IAM role used by crawlers (when enable_crawler = true)"
  type        = string
  default     = ""
}
