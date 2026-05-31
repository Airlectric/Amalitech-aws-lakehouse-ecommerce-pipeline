locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "glue-catalog"
    Project     = "lakehouse-ecommerce"
  }

  # Canonical Delta Lake table names.
  tables = ["products", "orders", "order_items"]
}
