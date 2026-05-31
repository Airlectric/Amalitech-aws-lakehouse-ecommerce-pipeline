locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "s3-data-lake"
    Project     = "lakehouse-ecommerce"
  }

  # Canonical bucket keys and their names.
  # raw           — landing zone for raw inbound data (EventBridge notifications on)
  # lakehouse-dwh — Delta Lake DWH zone (versioning required for Delta transaction log)
  # archived      — long-term cold archive
  # rejected      — quarantine for validation failures
  # glue-scripts  — Glue PySpark scripts
  # athena-results — Athena query results (short-lived, no versioning)
  # access-logs   — S3 server-access logs (no versioning, no KMS — must accept log delivery)
  bucket_names = {
    raw            = "${var.environment}-lakehouse-raw-${var.bucket_suffix}"
    lakehouse_dwh  = "${var.environment}-lakehouse-dwh-${var.bucket_suffix}"
    archived       = "${var.environment}-lakehouse-archived-${var.bucket_suffix}"
    rejected       = "${var.environment}-lakehouse-rejected-${var.bucket_suffix}"
    glue_scripts   = "${var.environment}-lakehouse-glue-scripts-${var.bucket_suffix}"
    athena_results = "${var.environment}-lakehouse-athena-results-${var.bucket_suffix}"
    access_logs    = "${var.environment}-lakehouse-access-logs-${var.bucket_suffix}"
  }

  # Buckets that should have versioning enabled.
  # athena-results and access-logs are excluded (ephemeral / log-only).
  versioned_buckets = {
    for k, v in local.bucket_names : k => v
    if !contains(["athena_results", "access_logs"], k)
  }

  # Buckets that receive server-access logging (all except the access-logs bucket itself).
  logged_buckets = {
    for k, v in local.bucket_names : k => v
    if k != "access_logs"
  }

  # All buckets get SSE-KMS except access_logs (log delivery requires SSE-S3 or no encryption).
  kms_encrypted_buckets = {
    for k, v in local.bucket_names : k => v
    if k != "access_logs"
  }
}
