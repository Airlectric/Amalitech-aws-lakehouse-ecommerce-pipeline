output "raw_bucket_id" {
  description = "ID of the raw landing zone S3 bucket"
  value       = module.s3_data_lake.raw_bucket_id
}

output "dwh_bucket_id" {
  description = "ID of the lakehouse DWH S3 bucket"
  value       = module.s3_data_lake.dwh_bucket_id
}

output "step_functions_arn" {
  description = "ARN of the lakehouse pipeline Step Functions state machine"
  value       = module.step_functions.state_machine_arn
}

output "sns_topic_arn" {
  description = "ARN of the lakehouse alerts SNS topic"
  value       = module.observability.sns_topic_arn
}

output "glue_catalog_database" {
  description = "Name of the Glue Catalog database"
  value       = module.glue_catalog.database_name
}

output "pipeline_dlq_arn" {
  description = "ARN of the pipeline dead-letter SQS queue"
  value       = module.lambda_functions.pipeline_dlq_arn
}
