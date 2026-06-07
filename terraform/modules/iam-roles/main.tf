data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ────────────────────────────────────────────────────────────────────────────
# GLUE ETL ROLE
# Used by all three PySpark jobs (products, orders, order_items).
# ────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "glue_etl" {
  name = "${var.environment}-glue-etl"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-etl" })
}

resource "aws_iam_role_policy_attachment" "glue_etl_service_role" {
  role       = aws_iam_role.glue_etl.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_etl_s3" {
  name = "${var.environment}-glue-etl-s3"
  role = aws_iam_role.glue_etl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRaw"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.raw_bucket_arn,
          "${var.raw_bucket_arn}/raw/*",
        ]
      },
      {
        Sid    = "ReadScripts"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.scripts_bucket_arn}/*",
        ]
      },
      {
        Sid    = "WriteScriptsTemp"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${var.scripts_bucket_arn}/temp/*",
        ]
      },
      {
        Sid    = "ReadWriteDwh"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:PutObject",
        ]
        Resource = [
          var.dwh_bucket_arn,
          "${var.dwh_bucket_arn}/*",
        ]
      },
      {
        Sid    = "WriteRejected"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:PutObject",
        ]
        Resource = [
          "${var.rejected_bucket_arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_etl_kms" {
  name = "${var.environment}-glue-etl-kms"
  role = aws_iam_role.glue_etl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "KmsDataLake"
      Effect   = "Allow"
      Action   = local.kms_decrypt
      Resource = [var.kms_key_arn]
    }]
  })
}

resource "aws_iam_role_policy" "glue_etl_catalog" {
  name = "${var.environment}-glue-etl-catalog"
  role = aws_iam_role.glue_etl.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "GlueCatalogRead"
      Effect = "Allow"
      Action = [
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:BatchGetPartition",
      ]
      Resource = [
        "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
        "arn:aws:glue:${var.aws_region}:${local.account_id}:database/${var.environment}_lakehouse_dwh",
        "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${var.environment}_lakehouse_dwh/*",
      ]
    }]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# LAMBDA ROUTER ROLE
# Runs outside the VPC (no vpc config needed). Triggered by EventBridge.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_router" {
  name = "${var.environment}-lambda-router"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-router" })
}

resource "aws_iam_role_policy_attachment" "lambda_router_basic" {
  role       = aws_iam_role.lambda_router.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_router_sfn_dlq" {
  name = "${var.environment}-lambda-router-sfn-dlq"
  role = aws_iam_role.lambda_router.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStateMachine"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [local.step_functions_arn]
      },
      {
        Sid      = "SendToDeadLetterQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [local.pipeline_dlq_arn]
      },
    ]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# LAMBDA ARCHIVER ROLE
# VPC-attached; called synchronously by Step Functions after all ETL jobs.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_archiver" {
  name = "${var.environment}-lambda-archiver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-archiver" })
}

resource "aws_iam_role_policy_attachment" "lambda_archiver_basic" {
  role       = aws_iam_role.lambda_archiver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role_policy" "lambda_archiver_s3" {
  name = "${var.environment}-lambda-archiver-s3"
  role = aws_iam_role.lambda_archiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDeleteRaw"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          var.raw_bucket_arn,
          "${var.raw_bucket_arn}/raw/*",
        ]
      },
      {
        Sid    = "WriteArchived"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = [
          "${var.archived_bucket_arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_archiver_kms" {
  name = "${var.environment}-lambda-archiver-kms"
  role = aws_iam_role.lambda_archiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "KmsDataLake"
      Effect   = "Allow"
      Action   = local.kms_encrypt_decrypt
      Resource = [var.kms_key_arn]
    }]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# STEP FUNCTIONS ROLE
# ────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "${var.environment}-step-functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-step-functions" })
}

resource "aws_iam_role_policy" "step_functions_glue" {
  name = "${var.environment}-sfn-glue"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartAndMonitorGlueJobs"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun",
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-products-etl",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-orders-etl",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-order-items-etl",
        ]
      },
      {
        Sid    = "PassRoleGlue"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.glue_etl.arn,
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "glue.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_lambda" {
  name = "${var.environment}-sfn-lambda"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokeLambdaFunctions"
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        local.lambda_archiver_arn,
      ]
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_sns" {
  name = "${var.environment}-sfn-sns"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PublishAlerts"
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = [var.sns_alert_topic_arn]
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_xray" {
  name = "${var.environment}-sfn-xray"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "XRayTracing"
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
      ]
      Resource = ["*"]
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_athena" {
  name = "${var.environment}-sfn-athena"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AthenaQueryExecution"
      Effect = "Allow"
      Action = [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
      ]
      Resource = [
        "arn:aws:athena:${var.aws_region}:${local.account_id}:workgroup/${var.environment}-analytics",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_states" {
  name = "${var.environment}-sfn-states"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "StartExpressStateMachines"
      Effect = "Allow"
      Action = ["states:StartExecution"]
      Resource = [
        "arn:aws:states:${var.aws_region}:${local.account_id}:stateMachine:${var.environment}-*",
      ]
    }]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# EVENTBRIDGE ROLE
# ────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "eventbridge" {
  name = "${var.environment}-eventbridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-eventbridge" })
}

resource "aws_iam_role_policy" "eventbridge_invoke" {
  name = "${var.environment}-eventbridge-invoke"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeRouterLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [local.lambda_router_arn]
      },
      {
        Sid      = "SendToDLQ"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [local.pipeline_dlq_arn]
      },
    ]
  })
}
