variable "environment" {
  description = "Environment name"
  type        = string
}

variable "glue_role_arns" {
  description = "ARNs of Glue IAM roles granted access to the Glue CMK"
  type        = list(string)
  default     = []
}

variable "lambda_role_arns" {
  description = "ARNs of Lambda IAM roles granted access to the s3-data-lake CMK"
  type        = list(string)
  default     = []
}

variable "additional_s3_role_arns" {
  description = "Any additional IAM role ARNs that need access to the s3-data-lake CMK"
  type        = list(string)
  default     = []
}
