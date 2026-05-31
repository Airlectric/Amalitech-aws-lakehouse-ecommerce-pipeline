locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "observability"
    Project     = "lakehouse-ecommerce"
  }

  dashboard_widgets = [
    # ── Step Functions overview ─────────────────────────────────────────────
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
    # ── Glue jobs ───────────────────────────────────────────────────────────
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
    # ── Lambda invocations / errors ─────────────────────────────────────────
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
    # ── DLQ depth ───────────────────────────────────────────────────────────
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
      }
    },
  ]
}
