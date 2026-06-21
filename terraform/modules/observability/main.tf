data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ────────────────────────────────────────────────────────────────────────────
# SNS ALERT TOPIC
# ────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-lakehouse-alerts"

  tags = merge(local.common_tags, { Name = "${var.environment}-lakehouse-alerts" })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH DASHBOARD
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "lakehouse" {
  dashboard_name = "${var.environment}-lakehouse-overview"
  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARMS – Step Functions
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sfn_executions_failed" {
  alarm_name          = "${var.environment}-sfn-executions-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "One or more Step Functions executions failed in the last 5 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.step_functions_state_machine_arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-sfn-executions-failed" })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARMS – Glue jobs (one per job via for_each)
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "glue_job_failed" {
  for_each = var.glue_job_names

  alarm_name          = "${var.environment}-glue-${each.key}-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedRuns"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Glue job ${each.value} recorded failed runs"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = each.value
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-${each.key}-failed" })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARMS – Lambda errors (one per function via for_each)
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.environment}-lambda-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Lambda function ${each.value} recorded errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-${each.key}-errors" })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARM – DLQ depth
# Any message landing in the DLQ indicates a delivery failure that needs
# attention; alert immediately.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  alarm_name          = "${var.environment}-pipeline-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "One or more messages are sitting in the pipeline DLQ"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.pipeline_dlq_name
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-dlq-messages" })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARM – SFN pipeline SLA (no successful execution in N hours)
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "sfn_sla_breach" {
  alarm_name          = "${var.environment}-pipeline-sla-breach"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsSucceeded"
  namespace           = "AWS/States"
  period              = tostring(var.sla_breach_hours * 3600)
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "No successful pipeline execution in ${var.sla_breach_hours} hours"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    StateMachineArn = var.step_functions_state_machine_arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-sla-breach" })
}

# ────────────────────────────────────────────────────────────────────────────
# ALARMS – DQ rejection rate per dataset (custom Lakehouse/DQ metric)
# Fires when > var.dq_rejection_rate_threshold % of rows are rejected,
# which could indicate a schema change or upstream data quality issue.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dq_rejection_rate" {
  for_each = toset(var.dataset_names)

  alarm_name          = "${var.environment}-dq-${each.key}-rejection-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RejectedRatePct"
  namespace           = "Lakehouse/DQ"
  period              = "86400"
  extended_statistic  = "p100"
  threshold           = tostring(var.dq_rejection_rate_threshold)
  alarm_description   = "${each.key} rejection rate exceeded ${var.dq_rejection_rate_threshold}% in the last 24 hours"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    Dataset = each.key
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-dq-${each.key}-rejection-rate-high" })
}

# ────────────────────────────────────────────────────────────────────────────
# CLOUDTRAIL – S3 DATA EVENTS + MANAGEMENT EVENTS
# Logs raw and DWH bucket data-plane events so every GetObject / PutObject
# call is auditable.  Management events cover IAM, Glue, Lambda API calls.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.environment}-lakehouse-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, { Name = "${var.environment}-cloudtrail-logs" })
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter { prefix = "" }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}

resource "aws_cloudtrail" "lakehouse" {
  name                          = "${var.environment}-lakehouse-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  # Management events (default: all read/write).
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # S3 data events: raw bucket.
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.raw_bucket_name}/"]
    }

    # S3 data events: DWH bucket.
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.dwh_bucket_name}/"]
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-lakehouse-trail" })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
