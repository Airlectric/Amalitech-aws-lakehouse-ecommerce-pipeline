variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "Availability zone for all subnets"
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "isolated_subnet_cidr" {
  description = "CIDR block for the isolated subnet"
  type        = string
  default     = "10.0.20.0/24"
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
