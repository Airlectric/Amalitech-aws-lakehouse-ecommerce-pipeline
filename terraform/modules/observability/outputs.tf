output "sns_topic_arn" {
  description = "ARN of the lakehouse alerts SNS topic"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the lakehouse alerts SNS topic"
  value       = aws_sns_topic.alerts.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.lakehouse.dashboard_name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.lakehouse.arn
}

output "cloudtrail_logs_bucket_id" {
  description = "ID (name) of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.id
}
