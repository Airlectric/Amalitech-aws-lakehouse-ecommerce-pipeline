variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bucket_suffix" {
  description = "Unique suffix appended to every bucket name (use AWS account ID to guarantee global uniqueness)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK used for SSE-KMS on all data lake buckets"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain S3 server-access logs in the access-logs bucket"
  type        = number
  default     = 365
}
