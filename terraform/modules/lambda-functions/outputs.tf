output "router_lambda_arn" {
  description = "ARN of the pipeline-router Lambda function"
  value       = aws_lambda_function.router.arn
}

output "archiver_lambda_arn" {
  description = "ARN of the file-archiver Lambda function"
  value       = aws_lambda_function.archiver.arn
}

output "pipeline_dlq_arn" {
  description = "ARN of the pipeline dead-letter SQS queue"
  value       = aws_sqs_queue.pipeline_dlq.arn
}

output "pipeline_dlq_url" {
  description = "URL of the pipeline dead-letter SQS queue"
  value       = aws_sqs_queue.pipeline_dlq.id
}

output "function_arns" {
  description = "Map of Lambda function ARNs by role"
  value = {
    router   = aws_lambda_function.router.arn
    archiver = aws_lambda_function.archiver.arn
  }
}

output "function_names" {
  description = "Map of Lambda function names by role"
  value = {
    router   = aws_lambda_function.router.function_name
    archiver = aws_lambda_function.archiver.function_name
  }
}
