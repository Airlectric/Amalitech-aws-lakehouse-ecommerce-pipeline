# ---------------------------------------------------------------------------
# Bucket creation
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  for_each = local.bucket_names

  bucket        = each.value
  force_destroy = false

  tags = merge(local.common_tags, { Name = each.key })
}

# ---------------------------------------------------------------------------
# Versioning — enabled for all zones except athena-results and access-logs
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  for_each = local.versioned_buckets

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# SSE-KMS — all buckets except access-logs (log delivery requires SSE-S3)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  for_each = local.kms_encrypted_buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# access-logs bucket uses SSE-S3 so the log-delivery service can write
resource "aws_s3_bucket_server_side_encryption_configuration" "sse_s3_access_logs" {
  bucket = aws_s3_bucket.this["access_logs"].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# ---------------------------------------------------------------------------
# Public access block — all buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.bucket_names

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Ownership controls — BucketOwnerEnforced on all buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.bucket_names

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# TLS-only bucket policy — all buckets
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.bucket_names

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this[each.key].arn,
          "${aws_s3_bucket.this[each.key].arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Server-access logging — all buckets except access-logs itself
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  for_each = local.logged_buckets

  bucket = aws_s3_bucket.this[each.key].id

  target_bucket = aws_s3_bucket.this["access_logs"].id
  target_prefix = "logs/${each.key}/"
}

# ---------------------------------------------------------------------------
# Lifecycle: raw — Std → IA@30d → Glacier@90d
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id

  rule {
    id     = "raw-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: lakehouse-dwh — Std → IA@90d (versioning kept for Delta history)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "lakehouse_dwh" {
  bucket = aws_s3_bucket.this["lakehouse_dwh"].id

  rule {
    id     = "dwh-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: archived — Std → Deep Archive@1d, expire@2555d (~7 years)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "archived" {
  bucket = aws_s3_bucket.this["archived"].id

  rule {
    id     = "archived-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 1
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: rejected — expire@90d
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "rejected" {
  bucket = aws_s3_bucket.this["rejected"].id

  rule {
    id     = "rejected-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: athena-results — expire@14d
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.this["athena_results"].id

  rule {
    id     = "athena-results-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: access-logs — expire@365d (configurable)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.this["access_logs"].id

  rule {
    id     = "access-logs-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

# ---------------------------------------------------------------------------
# EventBridge notifications on raw bucket (S3 → EventBridge for downstream triggers)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket = aws_s3_bucket.this["raw"].id

  eventbridge = true
}
