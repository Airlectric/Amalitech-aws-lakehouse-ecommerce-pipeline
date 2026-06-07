# ────────────────────────────────────────────────────────────────────────────
# PIPELINE DEAD-LETTER QUEUE
# Captures EventBridge → router delivery failures and router async failures
# so no trigger event is silently lost.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "pipeline_dlq" {
  name                      = "${var.environment}-pipeline-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true    # SSE-SQS encryption at rest

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-dlq" })
}

# Allow EventBridge to deliver failed-delivery events directly to the DLQ.
resource "aws_sqs_queue_policy" "pipeline_dlq" {
  queue_url = aws_sqs_queue.pipeline_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeDLQ"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.pipeline_dlq.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.environment}-*"
        }
      }
    }]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT PACKAGES
# ────────────────────────────────────────────────────────────────────────────
data "archive_file" "router" {
  type        = "zip"
  source_file = "${path.root}/../../../lambda/handlers/router.py"
  output_path = "${path.module}/builds/router.zip"
}

data "archive_file" "archiver" {
  type        = "zip"
  source_file = "${path.root}/../../../lambda/handlers/archiver.py"
  output_path = "${path.module}/builds/archiver.zip"
}

# ────────────────────────────────────────────────────────────────────────────
# PIPELINE ROUTER LAMBDA
# Runs outside the VPC: only calls SFN and SQS (both reachable over the
# public AWS service endpoints). Invoked asynchronously by EventBridge.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "router" {
  filename         = data.archive_file.router.output_path
  source_code_hash = data.archive_file.router.output_base64sha256
  function_name    = "${var.environment}-pipeline-router"
  role             = var.lambda_router_role_arn
  handler          = "router.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      STATE_MACHINE_ARN = local.step_functions_arn
    }
  }

  # EventBridge → Lambda is async; capture exhausted-retry events in the DLQ.
  dead_letter_config {
    target_arn = aws_sqs_queue.pipeline_dlq.arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-router" })
}

# Bound async retry behaviour: 2 retries, discard after 1 hour.
resource "aws_lambda_function_event_invoke_config" "router" {
  function_name                = aws_lambda_function.router.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

# ────────────────────────────────────────────────────────────────────────────
# FILE ARCHIVER LAMBDA
# Runs outside the VPC. Called synchronously by Step Functions at the end of
# the pipeline; it only copies/deletes objects in S3.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "archiver" {
  filename         = data.archive_file.archiver.output_path
  source_code_hash = data.archive_file.archiver.output_base64sha256
  function_name    = "${var.environment}-file-archiver"
  role             = var.lambda_archiver_role_arn
  handler          = "archiver.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256


  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      ARCHIVED_BUCKET = var.archived_bucket_id
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-file-archiver" })
}

# ────────────────────────────────────────────────────────────────────────────
# LAMBDA PERMISSIONS
# ────────────────────────────────────────────────────────────────────────────

# Allow any EventBridge rule in this account/region to invoke the router.
resource "aws_lambda_permission" "router_from_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.router.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.environment}-raw-s3-put"
}
