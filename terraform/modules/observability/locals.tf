locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "observability"
    Project     = "lakehouse-ecommerce"
  }

  dashboard_widgets = [
    # ── Row 1: Step Functions overview ─────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Step Functions – Executions"
        view   = "singleValue"
        region = var.aws_region
        period = 300
        metrics = [
          ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Started" }],
          ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Succeeded" }],
          ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Failed" }],
          ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "TimedOut" }],
        ]
      }
    },
    # ── Row 1: DLQ depth ───────────────────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Pipeline DLQ – Visible Messages"
        view   = "timeSeries"
        region = var.aws_region
        period = 300
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.pipeline_dlq_name, { stat = "Maximum", label = "DLQ Depth" }],
        ]
        yAxis = { left = { min = 0, showUnits = false } }
        annotations = {
          horizontal = [{ value = 1, label = "Alert threshold", color = "#ff6961" }]
        }
      }
    },
    # ── Row 2: Glue jobs ───────────────────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Glue Jobs – Runs"
        view   = "singleValue"
        region = var.aws_region
        period = 300
        metrics = [
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["products"], { stat = "Sum", label = "Products Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["products"], { stat = "Sum", label = "Products Failed" }],
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["orders"], { stat = "Sum", label = "Orders Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["orders"], { stat = "Sum", label = "Orders Failed" }],
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["order_items"], { stat = "Sum", label = "OrderItems Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["order_items"], { stat = "Sum", label = "OrderItems Failed" }],
        ]
      }
    },
    # ── Row 2: Lambda invocations / errors ─────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Lambda – Invocations and Errors"
        view   = "singleValue"
        region = var.aws_region
        period = 300
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["router"], { stat = "Sum", label = "Router Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["router"], { stat = "Sum", label = "Router Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["router"], { stat = "Average", label = "Router Duration (ms)" }],
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["archiver"], { stat = "Average", label = "Archiver Duration (ms)" }],
        ]
      }
    },
    # ── Row 3: DQ rejection rate per dataset ───────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "DQ – Rejection Rate by Dataset (%)"
        view   = "timeSeries"
        region = var.aws_region
        period = 86400
        metrics = [
          ["Lakehouse/DQ", "RejectedRatePct", "Dataset", "products", { stat = "p100", label = "Products" }],
          ["Lakehouse/DQ", "RejectedRatePct", "Dataset", "orders", { stat = "p100", label = "Orders" }],
          ["Lakehouse/DQ", "RejectedRatePct", "Dataset", "order_items", { stat = "p100", label = "Order Items" }],
        ]
        yAxis = { left = { min = 0, max = 100, showUnits = false } }
        annotations = {
          horizontal = [{ value = var.dq_rejection_rate_threshold, label = "Alert threshold", color = "#ff6961" }]
        }
      }
    },
    # ── Row 3: EventBridge ingest activity ─────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "EventBridge – Rule Invocations"
        view   = "timeSeries"
        region = var.aws_region
        period = 300
        metrics = [
          ["AWS/Events", "Invocations", "RuleName", var.eventbridge_rule_name, { stat = "Sum", label = "Invocations" }],
          ["AWS/Events", "FailedInvocations", "RuleName", var.eventbridge_rule_name, { stat = "Sum", label = "Failed" }],
        ]
        yAxis = { left = { min = 0, showUnits = false } }
      }
    },
    # ── Row 4: Alarm state panel ───────────────────────────────────────────
    {
      type   = "alarm"
      width  = 24
      height = 6
      properties = {
        title = "Alarm States"
        alarms = [
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-sfn-executions-failed",
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-pipeline-dlq-messages",
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-pipeline-sla-breach",
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-dq-products-rejection-rate-high",
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-dq-orders-rejection-rate-high",
          "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-dq-order_items-rejection-rate-high",
        ]
      }
    },
  ]
}
