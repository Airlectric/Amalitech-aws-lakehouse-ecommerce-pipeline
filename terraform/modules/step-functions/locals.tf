locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "step-functions"
    Project     = "lakehouse-ecommerce"
  }

  # Shared retry policy applied to every Glue task state.
  glue_retry = [
    {
      ErrorEquals     = ["States.TaskFailed", "Glue.AWSGlueException"]
      IntervalSeconds = 60
      MaxAttempts     = 2
      BackoffRate     = 2.0
    }
  ]

  # Shared catch clause: route any terminal error to the SNS notification state.
  glue_catch = [
    {
      ErrorEquals = ["States.ALL"]
      Next        = "NotifyFailure"
      ResultPath  = "$.error_info"
    }
  ]

  # ── Glue state helper: single-job run ─────────────────────────────────────
  products_etl_state = {
    Type           = "Task"
    Resource       = "arn:aws:states:::glue:startJobRun.sync"
    ResultPath     = "$.products_job"
    TimeoutSeconds = 3600
    Parameters = {
      JobName = var.products_etl_job_name
      Arguments = {
        "--run_date.$"    = "$.run_date"
        "--raw_bucket.$"  = "$.bucket"
        "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
        "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
      }
    }
    Next  = "ArchiveFile"
    Retry = local.glue_retry
    Catch = local.glue_catch
  }

  orders_etl_state = {
    Type           = "Task"
    Resource       = "arn:aws:states:::glue:startJobRun.sync"
    ResultPath     = "$.orders_job"
    TimeoutSeconds = 3600
    Parameters = {
      JobName = var.orders_etl_job_name
      Arguments = {
        "--run_date.$"    = "$.run_date"
        "--raw_bucket.$"  = "$.bucket"
        "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
        "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
      }
    }
    Next  = "ArchiveFile"
    Retry = local.glue_retry
    Catch = local.glue_catch
  }

  order_items_etl_state = {
    Type           = "Task"
    Resource       = "arn:aws:states:::glue:startJobRun.sync"
    ResultPath     = "$.order_items_job"
    TimeoutSeconds = 3600
    Parameters = {
      JobName = var.order_items_etl_job_name
      Arguments = {
        "--run_date.$"    = "$.run_date"
        "--raw_bucket.$"  = "$.bucket"
        "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
        "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
      }
    }
    Next  = "ArchiveFile"
    Retry = local.glue_retry
    Catch = local.glue_catch
  }

  # ── ASL definition ─────────────────────────────────────────────────────────
  definition = jsonencode({
    Comment = "Lakehouse E-Commerce ETL Pipeline – routes to per-dataset Glue job or runs all three in parallel"
    StartAt = "RouteByDataset"
    States = {

      # ── Routing ─────────────────────────────────────────────────────────────
      RouteByDataset = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.dataset"
            StringEquals = "products"
            Next         = "RunProductsETL"
          },
          {
            Variable     = "$.dataset"
            StringEquals = "orders"
            Next         = "RunOrdersETL"
          },
          {
            Variable     = "$.dataset"
            StringEquals = "order_items"
            Next         = "RunOrderItemsETL"
          },
        ]
        # When the trigger doesn't specify a dataset (e.g. daily full-load),
        # run all three jobs concurrently.
        Default = "RunAllParallel"
      }

      # ── Single-dataset paths ────────────────────────────────────────────────
      RunProductsETL   = local.products_etl_state
      RunOrdersETL     = local.orders_etl_state
      RunOrderItemsETL = local.order_items_etl_state

      # ── Full-load parallel branch ───────────────────────────────────────────
      RunAllParallel = {
        Type       = "Parallel"
        ResultPath = "$.parallel_results"
        Next       = "ArchiveFile"
        Retry      = local.glue_retry
        Catch      = local.glue_catch
        Branches = [
          {
            StartAt = "ParallelProducts"
            States = {
              ParallelProducts = {
                Type           = "Task"
                Resource       = "arn:aws:states:::glue:startJobRun.sync"
                ResultPath     = "$.products_job"
                TimeoutSeconds = 3600
                Parameters = {
                  JobName = var.products_etl_job_name
                  Arguments = {
                    "--run_date.$"    = "$.run_date"
                    "--raw_bucket.$"  = "$.bucket"
                    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
                    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
                  }
                }
                End = true
              }
            }
          },
          {
            StartAt = "ParallelOrders"
            States = {
              ParallelOrders = {
                Type           = "Task"
                Resource       = "arn:aws:states:::glue:startJobRun.sync"
                ResultPath     = "$.orders_job"
                TimeoutSeconds = 3600
                Parameters = {
                  JobName = var.orders_etl_job_name
                  Arguments = {
                    "--run_date.$"    = "$.run_date"
                    "--raw_bucket.$"  = "$.bucket"
                    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
                    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
                  }
                }
                End = true
              }
            }
          },
          {
            StartAt = "ParallelOrderItems"
            States = {
              ParallelOrderItems = {
                Type           = "Task"
                Resource       = "arn:aws:states:::glue:startJobRun.sync"
                ResultPath     = "$.order_items_job"
                TimeoutSeconds = 3600
                Parameters = {
                  JobName = var.order_items_etl_job_name
                  Arguments = {
                    "--run_date.$"    = "$.run_date"
                    "--raw_bucket.$"  = "$.bucket"
                    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
                    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
                  }
                }
                End = true
              }
            }
          },
        ]
      }

      # ── Post-ETL archiving ──────────────────────────────────────────────────
      ArchiveFile = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        ResultPath = "$.archive_result"
        Parameters = {
          FunctionName = var.archiver_lambda_arn
          "Payload.$"  = "$"
        }
        Next = "PipelineSucceeded"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }

      PipelineSucceeded = {
        Type = "Succeed"
      }

      # ── Failure notification ────────────────────────────────────────────────
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = var.sns_alert_topic_arn
          "Message.$" = "States.Format('Lakehouse pipeline failed. ExecutionId: {}. Error: {}. Cause: {}', $$.Execution.Id, $.error_info.Error, $.error_info.Cause)"
          "Subject.$" = "States.Format('[{}] Lakehouse Pipeline Failure', '${var.environment}')"
        }
        Next = "PipelineFailed"
      }

      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineExecutionFailed"
        Cause = "Pipeline execution failed; notification sent to SNS."
      }
    }
  })
}
