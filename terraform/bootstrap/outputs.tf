output "state_bucket_id" {
  description = "ID of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.state.arn
}

output "lock_table_id" {
  description = "ID of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.state_lock.id
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.state_lock.arn
}

output "kms_key_id" {
  description = "ID of the KMS CMK for state encryption"
  value       = aws_kms_key.state.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS CMK for state encryption"
  value       = aws_kms_key.state.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS CMK for state encryption"
  value       = aws_kms_alias.state.name
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions CI (plan-only)"
  value       = aws_iam_role.github_actions.arn
}


output "github_actions_plan_role_arn" {
  description = "ARN of the IAM role for GitHub Actions plan jobs"
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_apply_role_arn" {
  description = "ARN of the IAM role for manually approved GitHub Actions apply jobs"
  value       = aws_iam_role.github_actions_apply.arn
}
