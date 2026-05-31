variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  # Single AZ by default to minimise cost: each interface VPC endpoint is billed
  # per-AZ, so adding AZs would multiply the endpoint spend. Promote this to a
  # list and add more AZs here when HA is required.
  description = "Availability zone for all subnets (single-AZ by default for cost)"
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (holds the NAT Gateway)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (Glue + Lambda compute, NAT egress)"
  type        = string
  default     = "10.0.10.0/24"
}

variable "isolated_subnet_cidr" {
  description = "CIDR block for the isolated subnet (no internet route, S3/DDB gateway only)"
  type        = string
  default     = "10.0.20.0/24"
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for CloudWatch log group encryption (flow logs)"
  type        = string
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log retention in days for VPC flow logs"
  type        = number
  default     = 30
}
