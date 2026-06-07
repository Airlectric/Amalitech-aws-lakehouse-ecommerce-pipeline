# ────────────────────────────────────────────────────────────────────────────
# COMMON LIBRARY ZIP
# Packages glue/common/ with the package directory preserved so imports like
# `from common.schemas import ...` resolve in AWS Glue.
# ────────────────────────────────────────────────────────────────────────────
data "archive_file" "common_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../glue"
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
  source = "${path.root}/../../../glue/products_etl.py"
  etag   = filemd5("${path.root}/../../../glue/products_etl.py")

  tags = merge(local.common_tags, { Name = "products_etl.py" })
}

resource "aws_s3_object" "orders_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/orders_etl.py"
  source = "${path.root}/../../../glue/orders_etl.py"
  etag   = filemd5("${path.root}/../../../glue/orders_etl.py")

  tags = merge(local.common_tags, { Name = "orders_etl.py" })
}

resource "aws_s3_object" "order_items_etl_script" {
  bucket = var.scripts_bucket_id
  key    = "${local.script_key}/order_items_etl.py"
  source = "${path.root}/../../../glue/order_items_etl.py"
  etag   = filemd5("${path.root}/../../../glue/order_items_etl.py")

  tags = merge(local.common_tags, { Name = "order_items_etl.py" })
}


# ────────────────────────────────────────────────────────────────────────────
# PRODUCTS ETL JOB
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_job" "products_etl" {
  name              = "${var.environment}-products-etl"
  role_arn          = var.glue_etl_role_arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
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
  worker_type       = "G.1X"
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
  worker_type       = "G.1X"
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
