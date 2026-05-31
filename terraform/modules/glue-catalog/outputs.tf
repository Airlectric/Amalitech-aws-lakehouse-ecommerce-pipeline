output "database_name" {
  description = "Name of the Glue Catalog database"
  value       = aws_glue_catalog_database.dwh.name
}

output "glue_bronze_database_name" {
  description = "Alias for catalog compatibility – same as database_name"
  value       = aws_glue_catalog_database.dwh.name
}

output "table_names" {
  description = "Map of Glue Catalog table names by dataset"
  value = {
    products    = aws_glue_catalog_table.products.name
    orders      = aws_glue_catalog_table.orders.name
    order_items = aws_glue_catalog_table.order_items.name
  }
}

output "crawler_names" {
  description = "Map of Glue Crawler names by dataset (empty when enable_crawler = false)"
  value = {
    for k, v in aws_glue_crawler.dwh : k => v.name
  }
}
