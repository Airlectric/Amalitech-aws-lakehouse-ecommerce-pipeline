output "glue_etl_role_arn" {
  description = "ARN of the shared Glue ETL IAM role"
  value       = aws_iam_role.glue_etl.arn
}

output "lambda_router_role_arn" {
  description = "ARN of the Lambda pipeline-router IAM role"
  value       = aws_iam_role.lambda_router.arn
}

output "lambda_archiver_role_arn" {
  description = "ARN of the Lambda file-archiver IAM role"
  value       = aws_iam_role.lambda_archiver.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions IAM role"
  value       = aws_iam_role.step_functions.arn
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role"
  value       = aws_iam_role.eventbridge.arn
}

output "role_arns" {
  description = "Map of all IAM role ARNs by name"
  value = {
    glue_etl        = aws_iam_role.glue_etl.arn
    lambda_router   = aws_iam_role.lambda_router.arn
    lambda_archiver = aws_iam_role.lambda_archiver.arn
    step_functions  = aws_iam_role.step_functions.arn
    eventbridge     = aws_iam_role.eventbridge.arn
  }
}
