output "bucket_arns" {
  description = "Map of S3 bucket ARNs by zone key"
  value = {
    for k, b in aws_s3_bucket.this : k => b.arn
  }
}

output "bucket_ids" {
  description = "Map of S3 bucket IDs by zone key"
  value = {
    for k, b in aws_s3_bucket.this : k => b.id
  }
}

# ---- Individual bucket IDs ----

output "raw_bucket_id" {
  description = "ID of the raw landing zone bucket"
  value       = aws_s3_bucket.this["raw"].id
}

output "dwh_bucket_id" {
  description = "ID of the lakehouse DWH bucket (Delta Lake)"
  value       = aws_s3_bucket.this["lakehouse_dwh"].id
}

output "archived_bucket_id" {
  description = "ID of the archived (cold) bucket"
  value       = aws_s3_bucket.this["archived"].id
}

output "rejected_bucket_id" {
  description = "ID of the rejected / quarantine bucket"
  value       = aws_s3_bucket.this["rejected"].id
}

output "glue_scripts_bucket_id" {
  description = "ID of the Glue scripts bucket"
  value       = aws_s3_bucket.this["glue_scripts"].id
}

output "athena_results_bucket_id" {
  description = "ID of the Athena query results bucket"
  value       = aws_s3_bucket.this["athena_results"].id
}

output "access_logs_bucket_id" {
  description = "ID of the S3 server-access logs bucket"
  value       = aws_s3_bucket.this["access_logs"].id
}

# ---- Individual bucket ARNs ----

output "raw_bucket_arn" {
  description = "ARN of the raw landing zone bucket"
  value       = aws_s3_bucket.this["raw"].arn
}

output "dwh_bucket_arn" {
  description = "ARN of the lakehouse DWH bucket (Delta Lake)"
  value       = aws_s3_bucket.this["lakehouse_dwh"].arn
}

output "archived_bucket_arn" {
  description = "ARN of the archived (cold) bucket"
  value       = aws_s3_bucket.this["archived"].arn
}

output "rejected_bucket_arn" {
  description = "ARN of the rejected / quarantine bucket"
  value       = aws_s3_bucket.this["rejected"].arn
}

output "glue_scripts_bucket_arn" {
  description = "ARN of the Glue scripts bucket"
  value       = aws_s3_bucket.this["glue_scripts"].arn
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query results bucket"
  value       = aws_s3_bucket.this["athena_results"].arn
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 server-access logs bucket"
  value       = aws_s3_bucket.this["access_logs"].arn
}
