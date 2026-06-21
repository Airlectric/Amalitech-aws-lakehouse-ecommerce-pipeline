output "products_etl_job_name" {
  description = "Name of the Products ETL Glue job"
  value       = aws_glue_job.products_etl.name
}

output "orders_etl_job_name" {
  description = "Name of the Orders ETL Glue job"
  value       = aws_glue_job.orders_etl.name
}

output "order_items_etl_job_name" {
  description = "Name of the Order Items ETL Glue job"
  value       = aws_glue_job.order_items_etl.name
}


output "job_names" {
  description = "Map of Glue job names by dataset (used by observability alarms)"
  value = {
    products    = aws_glue_job.products_etl.name
    orders      = aws_glue_job.orders_etl.name
    order_items = aws_glue_job.order_items_etl.name
    maintenance = aws_glue_job.maintenance.name
  }
}
