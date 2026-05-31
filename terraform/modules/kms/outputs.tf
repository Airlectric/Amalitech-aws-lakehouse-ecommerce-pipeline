output "key_arns" {
  description = "Map of KMS key ARNs by domain name"
  value = {
    for k, key in aws_kms_key.this : k => key.arn
  }
}

output "key_ids" {
  description = "Map of KMS key IDs by domain name"
  value = {
    for k, key in aws_kms_key.this : k => key.key_id
  }
}

output "key_aliases" {
  description = "Map of KMS key aliases by domain name"
  value = {
    for k, alias in aws_kms_alias.this : k => alias.name
  }
}

output "s3_data_lake_key_arn" {
  description = "ARN of the S3 data lake KMS CMK"
  value       = aws_kms_key.this["s3-data-lake"].arn
}

output "glue_key_arn" {
  description = "ARN of the Glue KMS CMK"
  value       = aws_kms_key.this["glue"].arn
}

output "logs_key_arn" {
  description = "ARN of the CloudWatch logs KMS CMK"
  value       = aws_kms_key.this["logs"].arn
}
