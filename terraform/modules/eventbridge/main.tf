# ────────────────────────────────────────────────────────────────────────────
# EVENTBRIDGE RULE
# Fires on every S3 Object Created event under the raw/ prefix on the
# raw bucket.  EventBridge S3 notifications require that the bucket has
# EventBridge notifications enabled (done in the s3-data-lake module).
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "raw_s3_put" {
  name        = "${var.environment}-raw-s3-put"
  description = "Capture S3 Object Created events on the raw bucket under raw/"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [var.raw_bucket_id]
      }
      object = {
        key = [
          { prefix = "raw/" }
        ]
      }
    }
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-raw-s3-put" })
}

# ────────────────────────────────────────────────────────────────────────────
# TARGET: PIPELINE ROUTER LAMBDA
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_event_target" "router_lambda" {
  rule      = aws_cloudwatch_event_rule.raw_s3_put.name
  target_id = "PipelineRouterLambda"
  arn       = var.router_lambda_arn
  role_arn  = var.eventbridge_role_arn

  # Retry up to 2 times over at most 1 hour before sending to the DLQ.
  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 3600
  }

  dead_letter_config {
    arn = var.dlq_arn
  }
}

