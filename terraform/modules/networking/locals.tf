locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "networking"
    Project     = "lakehouse-ecommerce"
  }

  # Interface endpoints placed in the private subnet.
  # glue private_dns=false: Glue uses the regional endpoint URL directly.
  interface_endpoint_services = {
    glue       = { service = "glue", private_dns = false }
    states     = { service = "states", private_dns = true }
    kms        = { service = "kms", private_dns = true }
    logs       = { service = "logs", private_dns = true }
    monitoring = { service = "monitoring", private_dns = true }
    sns        = { service = "sns", private_dns = true }
    sts        = { service = "sts", private_dns = true }
    athena     = { service = "athena", private_dns = true }
  }

  # Gateway endpoints routed into both private and isolated route tables.
  gateway_endpoint_services = {
    s3       = { service = "s3" }
    dynamodb = { service = "dynamodb" }
  }
}
