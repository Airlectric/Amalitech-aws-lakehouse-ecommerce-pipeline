locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "athena"
    Project     = "lakehouse-ecommerce"
  }
}
