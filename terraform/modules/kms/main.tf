data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  for_each = local.keys

  description             = each.value.description
  deletion_window_in_days = 30
  enable_key_rotation     = true
  is_enabled              = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
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
        Sid    = "AllowServicePrincipalAccess"
        Effect = "Allow"
        Principal = {
          Service = each.value.service_principals
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
      ], length(each.value.role_arns) > 0 ? [
      {
        Sid    = "AllowRoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = each.value.role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ] : [])
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-${each.key}" })
}

resource "aws_kms_alias" "this" {
  for_each = aws_kms_key.this

  name          = "alias/${var.environment}/${each.key}"
  target_key_id = each.value.key_id
}
