data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.environment}-lakehouse-vpc" })
}

# ---------------------------------------------------------------------------
# Subnets — public / private / isolated (single AZ for cost)
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "${var.environment}-public-${var.availability_zone}" })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "${var.environment}-private-${var.availability_zone}" })
}

resource "aws_subnet" "isolated" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.isolated_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "${var.environment}-isolated-${var.availability_zone}" })
}

# ---------------------------------------------------------------------------
# Internet Gateway (attached to public subnet)
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-igw" })
}

# ---------------------------------------------------------------------------
# NAT Gateway (single, in public subnet — cost optimisation)
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${var.environment}-nat-eip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = merge(local.common_tags, { Name = "${var.environment}-nat-gw" })

  depends_on = [aws_internet_gateway.main]
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------

# Public route table — default route via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table — default route via NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-private-rt" })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Isolated route table — NO internet route; only gateway endpoints reach S3/DDB
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-isolated-rt" })
}

resource "aws_route_table_association" "isolated" {
  subnet_id      = aws_subnet.isolated.id
  route_table_id = aws_route_table.isolated.id
}

# ---------------------------------------------------------------------------
# Gateway VPC Endpoints — S3 and DynamoDB
# Routes injected into BOTH private and isolated route tables
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoint_services

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.value.service}"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.isolated.id,
  ]

  tags = merge(local.common_tags, { Name = "${var.environment}-gw-${each.key}" })
}

# ---------------------------------------------------------------------------
# Interface VPC Endpoints — placed in private subnet
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.${each.value.service}"
  vpc_endpoint_type = "Interface"

  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = try(each.value.private_dns, true)

  tags = merge(local.common_tags, { Name = "${var.environment}-vpce-${each.key}" })
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  name        = "${var.environment}-vpc-endpoints"
  description = "Security group for VPC interface endpoints — allows HTTPS from Glue and Lambda"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-vpc-endpoints-sg" })
}

resource "aws_security_group" "glue" {
  name        = "${var.environment}-glue"
  description = "Security group for AWS Glue jobs"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-sg" })
}

resource "aws_security_group" "lambda" {
  name        = "${var.environment}-lambda"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-sg" })
}

# Endpoints SG: accept HTTPS from Glue
resource "aws_security_group_rule" "endpoints_ingress_glue" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.glue.id
  security_group_id        = aws_security_group.endpoints.id
  description              = "HTTPS from Glue security group"
}

# Endpoints SG: accept HTTPS from Lambda
resource "aws_security_group_rule" "endpoints_ingress_lambda" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  security_group_id        = aws_security_group.endpoints.id
  description              = "HTTPS from Lambda security group"
}

# Glue SG: egress to interface endpoints
resource "aws_security_group_rule" "glue_egress_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.endpoints.id
  security_group_id        = aws_security_group.glue.id
  description              = "HTTPS to VPC interface endpoints"
}

# Glue SG: egress to S3 via gateway endpoint prefix list
resource "aws_security_group_rule" "glue_egress_s3_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.gateway["s3"].prefix_list_id]
  security_group_id = aws_security_group.glue.id
  description       = "HTTPS to S3 via gateway endpoint prefix list"
}

# Glue SG: egress to DynamoDB via gateway endpoint prefix list
resource "aws_security_group_rule" "glue_egress_dynamodb_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.gateway["dynamodb"].prefix_list_id]
  security_group_id = aws_security_group.glue.id
  description       = "HTTPS to DynamoDB via gateway endpoint prefix list"
}

# Lambda SG: egress to interface endpoints
resource "aws_security_group_rule" "lambda_egress_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.endpoints.id
  security_group_id        = aws_security_group.lambda.id
  description              = "HTTPS to VPC interface endpoints"
}

# Lambda SG: egress to S3 via gateway endpoint prefix list
resource "aws_security_group_rule" "lambda_egress_s3_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.gateway["s3"].prefix_list_id]
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to S3 via gateway endpoint prefix list"
}

# Lambda SG: egress to DynamoDB via gateway endpoint prefix list
resource "aws_security_group_rule" "lambda_egress_dynamodb_gateway" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [aws_vpc_endpoint.gateway["dynamodb"].prefix_list_id]
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to DynamoDB via gateway endpoint prefix list"
}

# ---------------------------------------------------------------------------
# VPC Flow Logs → CloudWatch (KMS-encrypted)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.environment}-lakehouse"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.common_tags, { Name = "${var.environment}-vpc-flow-logs" })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.environment}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-vpc-flow-logs-role" })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.environment}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-vpc-flow-log" })
}

# ---------------------------------------------------------------------------
# Default network ACL — restrict to VPC-internal + allow full egress
# ---------------------------------------------------------------------------
resource "aws_default_network_acl" "main" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id
  subnet_ids = [
    aws_subnet.public.id,
    aws_subnet.private.id,
    aws_subnet.isolated.id,
  ]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-default-nacl" })
}

# Lock down the default security group (no rules, self-only)
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  ingress {
    protocol  = "-1"
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    protocol  = "-1"
    self      = true
    from_port = 0
    to_port   = 0
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-default-sg" })
}
