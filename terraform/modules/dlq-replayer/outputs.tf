output "replayer_lambda_arn" {
  description = "ARN of the DLQ replayer Lambda function"
  value       = aws_lambda_function.dlq_replayer.arn
}
