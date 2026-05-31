locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "kms"
    Project     = "lakehouse-ecommerce"
  }

  keys = {
    s3-data-lake = {
      description        = "KMS CMK for S3 data lake zone encryption (raw, dwh, archived, rejected, scripts)"
      service_principals = ["s3.amazonaws.com"]
      role_arns          = concat(var.lambda_role_arns, var.additional_s3_role_arns)
    }
    glue = {
      description        = "KMS CMK for Glue job encryption (bookmarks, spark logs, shuffle)"
      service_principals = ["glue.amazonaws.com"]
      role_arns          = var.glue_role_arns
    }
    logs = {
      description        = "KMS CMK for CloudWatch log group encryption"
      service_principals = ["logs.amazonaws.com", "logs.us-east-1.amazonaws.com"]
      role_arns          = []
    }
  }
}
