# ────────────────────────────────────────────────────────────────────────────
# COMMON LIBRARY ZIP
# Packages glue/common/ with the package directory preserved so imports like
# `from common.schemas import ...` resolve in AWS Glue.
# ────────────────────────────────────────────────────────────────────────────
data "archive_file" "common_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../src/glue_jobs"
  output_path = "${path.module}/builds/common.zip"
}

resource "aws_s3_object" "common_zip" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/common.zip"
  source = data.archive_file.common_zip.output_path
  etag   = data.archive_file.common_zip.output_md5

  tags = merge(local.common_tags, { Name = "common.zip" })
}

# ────────────────────────────────────────────────────────────────────────────
# SCRIPT UPLOADS
# ────────────────────────────────────────────────────────────────────────────
resource "aws_s3_object" "products_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/products_etl.py"
  source = "${path.root}/../../../src/glue_jobs/products_etl.py"
  etag   = filemd5("${path.root}/../../../src/glue_jobs/products_etl.py")

  tags = merge(local.common_tags, { Name = "products_etl.py" })
}

resource "aws_s3_object" "orders_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/orders_etl.py"
  source = "${path.root}/../../../src/glue_jobs/orders_etl.py"
  etag   = filemd5("${path.root}/../../../src/glue_jobs/orders_etl.py")

  tags = merge(local.common_tags, { Name = "orders_etl.py" })
}

resource "aws_s3_object" "order_items_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/order_items_etl.py"
  source = "${path.root}/../../../src/glue_jobs/order_items_etl.py"
  etag   = filemd5("${path.root}/../../../src/glue_jobs/order_items_etl.py")

  tags = merge(local.common_tags, { Name = "order_items_etl.py" })
}


resource "aws_s3_object" "maintenance_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/maintenance_etl.py"
  source = "${path.root}/../../../src/glue_jobs/maintenance_etl.py"
  etag   = filemd5("${path.root}/../../../src/glue_jobs/maintenance_etl.py")

  tags = merge(local.common_tags, { Name = "maintenance_etl.py" })
}

# ────────────────────────────────────────────────────────────────────────────
# DELTA MAINTENANCE JOB
# Runs OPTIMIZE + VACUUM on all three Delta tables once per day.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "maintenance" {
  name              = "${var.environment}-delta-maintenance"
  role_arn          = var.glue_etl_role_arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  max_retries = 0
  timeout     = 60

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_id}/${local.script_key}/maintenance_etl.py"
    python_version  = "3.9"
  }

  default_arguments = merge(local.common_job_args, {
    "--TempDir"             = "s3://${var.scripts_bucket_id}/temp/${var.environment}/maintenance/"
    "--dwh_path"            = "s3://${var.dwh_bucket_id}/dwh"
    "--vacuum_retain_hours" = tostring(var.vacuum_retain_hours)
  })

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-delta-maintenance" })

  depends_on = [aws_s3_object.maintenance_etl_script, aws_s3_object.common_zip]
}

# ────────────────────────────────────────────────────────────────────────────
# EVENTBRIDGE SCHEDULER — daily maintenance trigger
# ────────────────────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "glue_scheduler" {
  name = "${var.environment}-glue-maintenance-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-maintenance-scheduler" })
}

resource "aws_iam_role_policy" "glue_scheduler_start_job" {
  name = "${var.environment}-scheduler-start-maintenance"
  role = aws_iam_role.glue_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "StartMaintenanceJob"
      Effect = "Allow"
      Action = ["glue:StartJobRun"]
      Resource = [
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.maintenance.name}",
      ]
    }]
  })
}

resource "aws_scheduler_schedule" "maintenance" {
  name       = "${var.environment}-delta-maintenance"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.maintenance_schedule
  schedule_expression_timezone = "UTC"

  target {
    arn      = "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.maintenance.name}"
    role_arn = aws_iam_role.glue_scheduler.arn

    input = jsonencode({
      Arguments = {
        "--dwh_path"            = "s3://${var.dwh_bucket_id}/dwh"
        "--vacuum_retain_hours" = tostring(var.vacuum_retain_hours)
      }
    })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────
# PRODUCTS ETL JOB
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "products_etl" {
  name              = "${var.environment}-products-etl"
  role_arn          = var.glue_etl_role_arn
  glue_version      = "4.0"
  worker_type       = var.worker_type
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_id}/${local.script_key}/products_etl.py"
    python_version  = "3.9"
  }

  default_arguments = merge(local.common_job_args, {
    "--TempDir"       = "s3://${var.scripts_bucket_id}/temp/${var.environment}/products/"
    "--raw_bucket"    = var.raw_bucket_id
    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
    "--run_date"      = ""
  })

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-products-etl" })

  depends_on = [aws_s3_object.products_etl_script, aws_s3_object.common_zip]
}

# ────────────────────────────────────────────────────────────────────────────
# ORDERS ETL JOB
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "orders_etl" {
  name              = "${var.environment}-orders-etl"
  role_arn          = var.glue_etl_role_arn
  glue_version      = "4.0"
  worker_type       = var.worker_type
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_id}/${local.script_key}/orders_etl.py"
    python_version  = "3.9"
  }

  default_arguments = merge(local.common_job_args, {
    "--TempDir"       = "s3://${var.scripts_bucket_id}/temp/${var.environment}/orders/"
    "--raw_bucket"    = var.raw_bucket_id
    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
    "--run_date"      = ""
  })

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-orders-etl" })

  depends_on = [aws_s3_object.orders_etl_script, aws_s3_object.common_zip]
}

# ────────────────────────────────────────────────────────────────────────────
# ORDER ITEMS ETL JOB
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "order_items_etl" {
  name              = "${var.environment}-order-items-etl"
  role_arn          = var.glue_etl_role_arn
  glue_version      = "4.0"
  worker_type       = var.worker_type
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_id}/${local.script_key}/order_items_etl.py"
    python_version  = "3.9"
  }

  default_arguments = merge(local.common_job_args, {
    "--TempDir"       = "s3://${var.scripts_bucket_id}/temp/${var.environment}/order_items/"
    "--raw_bucket"    = var.raw_bucket_id
    "--dwh_path"      = "s3://${var.dwh_bucket_id}/dwh"
    "--rejected_path" = "s3://${var.rejected_bucket_id}/rejected"
    "--run_date"      = ""
  })

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-order-items-etl" })

  depends_on = [aws_s3_object.order_items_etl_script, aws_s3_object.common_zip]
}
