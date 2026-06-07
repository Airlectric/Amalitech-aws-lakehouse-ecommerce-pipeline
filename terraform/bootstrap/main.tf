data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# KMS key for state backend encryption (S3 + DynamoDB)
# ---------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "KMS CMK for Terraform state backend encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAdminFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowS3DynamoDbServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-state-backend-kms" })
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.environment}/lakehouse-state-backend"
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# S3 state bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = merge(local.common_tags, { Name = "${var.environment}-terraform-state" })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.state.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# DynamoDB state lock table
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "state_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-terraform-state-lock" })
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider + CI role (plan-only)
# ---------------------------------------------------------------------------
# The OIDC provider for token.actions.githubusercontent.com is account-wide
# (one per account). P1 bootstrap already created it; reference it here.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# The CI pipeline is PLAN-ONLY (fmt / validate / plan). It therefore needs
# read access to every service for `plan` to refresh state, plus read/write
# to the state backend so `init`/`plan` can load and lock state. It does NOT
# need broad create/modify/delete or iam:PassRole. If a gated `apply` pipeline
# is added later, give it a SEPARATE, narrowly-scoped role rather than
# widening this one.
resource "aws_iam_role" "github_actions" {
  name = "${var.environment}-lakehouse-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDC"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lakehouse-github-actions" })
}

resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "github_actions_state_backend" {
  name = "${var.environment}-lakehouse-state-backend"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageStateBackend"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
          aws_dynamodb_table.state_lock.arn,
          aws_kms_key.state.arn,
        ]
      },
    ]
  })
}


# ---------------------------------------------------------------------------
# GitHub OIDC apply role (manual, protected environment only)
# ---------------------------------------------------------------------------
# This role is intentionally separate from the plan role. It has broad apply
# permissions for this training project, but GitHub can only assume it from the
# protected `dev` environment subject.
resource "aws_iam_role" "github_actions_apply" {
  name = "${var.environment}-lakehouse-github-actions-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDCApplyEnvironment"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:environment:${var.environment}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name             = "${var.environment}-lakehouse-github-actions-apply"
    DeploymentAccess = "apply"
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_apply_admin" {
  role       = aws_iam_role.github_actions_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
