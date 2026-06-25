locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ── IAM role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "dlq_replayer" {
  name = "${var.environment}-dlq-replayer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-dlq-replayer-role" })
}

resource "aws_iam_role_policy" "dlq_replayer" {
  name = "${var.environment}-dlq-replayer-policy"
  role = aws_iam_role.dlq_replayer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDeleteDLQ"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = var.dlq_arn
      },
      {
        Sid      = "StartSFNExecution"
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = var.state_machine_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.dlq_replayer.arn}:*"
      },
    ]
  })
}

# ── Lambda zip ────────────────────────────────────────────────────────────────
data "archive_file" "dlq_replayer" {
  type        = "zip"
  source_file = "${path.root}/../../../src/lambda_functions/dlq_replayer.py"
  output_path = "${path.module}/dlq_replayer.zip"
}

# ── Lambda function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "dlq_replayer" {
  function_name    = "${var.environment}-dlq-replayer"
  role             = aws_iam_role.dlq_replayer.arn
  handler          = "dlq_replayer.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dlq_replayer.output_path
  source_code_hash = data.archive_file.dlq_replayer.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      STATE_MACHINE_ARN = var.state_machine_arn
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-dlq-replayer" })

  depends_on = [aws_cloudwatch_log_group.dlq_replayer]
}

# ── SQS event source mapping ──────────────────────────────────────────────────
resource "aws_lambda_event_source_mapping" "dlq" {
  event_source_arn                   = var.dlq_arn
  function_name                      = aws_lambda_function.dlq_replayer.arn
  batch_size                         = 1
  maximum_batching_window_in_seconds = 0
  enabled                            = true

  function_response_types = ["ReportBatchItemFailures"]
}

# ── CloudWatch log group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "dlq_replayer" {
  name              = "/aws/lambda/${var.environment}-dlq-replayer"
  retention_in_days = 30

  tags = merge(local.common_tags, { Name = "${var.environment}-dlq-replayer-logs" })
}
