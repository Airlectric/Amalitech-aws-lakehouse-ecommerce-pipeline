variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "lakehouse-terraform-state-lock"
}

variable "aws_region" {
  description = "AWS region for the state backend"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' for OIDC trust policy"
  type        = string
  default     = ""
}
