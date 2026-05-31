locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "eventbridge"
    Project     = "lakehouse-ecommerce"
  }
}
