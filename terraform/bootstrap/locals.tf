locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "state-backend"
    Project     = "lakehouse-ecommerce"
  }
}
