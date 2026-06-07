# ============================================================================
# Project 2 – Lakehouse e-commerce pipeline
# Environment: dev
# ============================================================================

# ── KMS keys ─────────────────────────────────────────────────────────────────
module "kms" {
  source      = "../../modules/kms"
  environment = var.environment
}


# ── S3 data lake buckets ──────────────────────────────────────────────────────
module "s3_data_lake" {
  source      = "../../modules/s3-data-lake"
  environment = var.environment

  bucket_suffix = var.bucket_suffix
  kms_key_arn   = module.kms.s3_data_lake_key_arn
}

# ── Glue Catalog (database + tables + optional crawlers) ─────────────────────
module "glue_catalog" {
  source      = "../../modules/glue-catalog"
  environment = var.environment

  dwh_bucket_id     = module.s3_data_lake.dwh_bucket_id
  enable_crawler    = var.enable_crawler
  glue_etl_role_arn = module.iam_roles.glue_etl_role_arn
}

# ── IAM roles ────────────────────────────────────────────────────────────────
module "iam_roles" {
  source      = "../../modules/iam-roles"
  environment = var.environment
  aws_region  = var.aws_region

  raw_bucket_arn      = module.s3_data_lake.raw_bucket_arn
  scripts_bucket_arn  = module.s3_data_lake.glue_scripts_bucket_arn
  dwh_bucket_arn      = module.s3_data_lake.dwh_bucket_arn
  rejected_bucket_arn = module.s3_data_lake.rejected_bucket_arn
  archived_bucket_arn = module.s3_data_lake.archived_bucket_arn
  kms_key_arn         = module.kms.s3_data_lake_key_arn
  sns_alert_topic_arn = module.observability.sns_topic_arn
}

# ── Glue ETL jobs ─────────────────────────────────────────────────────────────
module "glue_jobs" {
  source      = "../../modules/glue-jobs"
  environment = var.environment

  scripts_bucket_id  = module.s3_data_lake.glue_scripts_bucket_id
  raw_bucket_id      = module.s3_data_lake.raw_bucket_id
  dwh_bucket_id      = module.s3_data_lake.dwh_bucket_id
  rejected_bucket_id = module.s3_data_lake.rejected_bucket_id
  glue_etl_role_arn  = module.iam_roles.glue_etl_role_arn


  worker_count    = var.worker_count
  max_retries     = var.glue_max_retries
  timeout_minutes = var.glue_timeout_minutes
}

# ── Lambda functions (router + archiver) ─────────────────────────────────────
module "lambda_functions" {
  source      = "../../modules/lambda-functions"
  environment = var.environment

  archived_bucket_id       = module.s3_data_lake.archived_bucket_id
  lambda_router_role_arn   = module.iam_roles.lambda_router_role_arn
  lambda_archiver_role_arn = module.iam_roles.lambda_archiver_role_arn
}

# ── Step Functions state machine ─────────────────────────────────────────────
module "step_functions" {
  source      = "../../modules/step-functions"
  environment = var.environment

  step_functions_role_arn  = module.iam_roles.step_functions_role_arn
  products_etl_job_name    = module.glue_jobs.products_etl_job_name
  orders_etl_job_name      = module.glue_jobs.orders_etl_job_name
  order_items_etl_job_name = module.glue_jobs.order_items_etl_job_name
  archiver_lambda_arn      = module.lambda_functions.archiver_lambda_arn
  sns_alert_topic_arn      = module.observability.sns_topic_arn
  dwh_bucket_id            = module.s3_data_lake.dwh_bucket_id
  rejected_bucket_id       = module.s3_data_lake.rejected_bucket_id
}

# ── EventBridge rule (S3 Object Created → router Lambda) ─────────────────────
module "eventbridge" {
  source      = "../../modules/eventbridge"
  environment = var.environment

  raw_bucket_id        = module.s3_data_lake.raw_bucket_id
  router_lambda_arn    = module.lambda_functions.router_lambda_arn
  eventbridge_role_arn = module.iam_roles.eventbridge_role_arn
  dlq_arn              = module.lambda_functions.pipeline_dlq_arn
}

# ── Athena workgroup + query result location ──────────────────────────────────
module "athena" {
  source      = "../../modules/athena"
  environment = var.environment

  athena_results_bucket_id = module.s3_data_lake.athena_results_bucket_id
  kms_key_arn              = module.kms.s3_data_lake_key_arn
}

# ── Observability (SNS, CloudWatch alarms + dashboard, CloudTrail) ────────────
module "observability" {
  source      = "../../modules/observability"
  environment = var.environment
  aws_region  = var.aws_region

  glue_job_names                   = module.glue_jobs.job_names
  lambda_function_names            = module.lambda_functions.function_names
  step_functions_state_machine_arn = module.step_functions.state_machine_arn
  pipeline_dlq_arn                 = module.lambda_functions.pipeline_dlq_arn
  pipeline_dlq_name                = "${var.environment}-pipeline-dlq"
  raw_bucket_name                  = module.s3_data_lake.raw_bucket_id
  dwh_bucket_name                  = module.s3_data_lake.dwh_bucket_id
  kms_key_arn                      = module.kms.s3_data_lake_key_arn
  alert_emails                     = var.alert_emails
  eventbridge_rule_name            = module.eventbridge.event_rule_name
}
