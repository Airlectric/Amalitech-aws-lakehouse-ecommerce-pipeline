# ────────────────────────────────────────────────────────────────────────────
# GLUE CATALOG DATABASE
# Single database for all DWH Delta tables.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_catalog_database" "dwh" {
  name         = "${var.environment}_lakehouse_dwh"
  description  = "Lakehouse DWH – Delta Lake tables for products, orders and order_items"
  location_uri = "s3://${var.dwh_bucket_id}/dwh/"
}

# ────────────────────────────────────────────────────────────────────────────
# PRODUCTS DELTA TABLE
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "products" {
  name          = "products"
  database_name = aws_glue_catalog_database.dwh.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                     = "TRUE"
    "spark.sql.sources.provider" = "delta"
    classification               = "delta"
  }

  storage_descriptor {
    location      = "s3://${var.dwh_bucket_id}/dwh/products/"
    input_format  = "org.apache.hadoop.mapred.FileInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "product_name"
      type = "string"
    }
    columns {
      name = "category"
      type = "string"
    }
    columns {
      name = "price"
      type = "double"
    }
    columns {
      name = "stock_quantity"
      type = "int"
    }
    columns {
      name = "created_at"
      type = "string"
    }
    columns {
      name = "updated_at"
      type = "string"
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────
# ORDERS DELTA TABLE
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "orders" {
  name          = "orders"
  database_name = aws_glue_catalog_database.dwh.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                     = "TRUE"
    "spark.sql.sources.provider" = "delta"
    classification               = "delta"
  }

  storage_descriptor {
    location      = "s3://${var.dwh_bucket_id}/dwh/orders/"
    input_format  = "org.apache.hadoop.mapred.FileInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "order_id"
      type = "string"
    }
    columns {
      name = "customer_id"
      type = "string"
    }
    columns {
      name = "order_status"
      type = "string"
    }
    columns {
      name = "order_date"
      type = "string"
    }
    columns {
      name = "total_amount"
      type = "double"
    }
    columns {
      name = "created_at"
      type = "string"
    }
    columns {
      name = "updated_at"
      type = "string"
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────
# ORDER ITEMS DELTA TABLE
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "order_items" {
  name          = "order_items"
  database_name = aws_glue_catalog_database.dwh.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                     = "TRUE"
    "spark.sql.sources.provider" = "delta"
    classification               = "delta"
  }

  storage_descriptor {
    location      = "s3://${var.dwh_bucket_id}/dwh/order_items/"
    input_format  = "org.apache.hadoop.mapred.FileInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "order_item_id"
      type = "string"
    }
    columns {
      name = "order_id"
      type = "string"
    }
    columns {
      name = "product_id"
      type = "string"
    }
    columns {
      name = "quantity"
      type = "int"
    }
    columns {
      name = "unit_price"
      type = "double"
    }
    columns {
      name = "line_total"
      type = "double"
    }
    columns {
      name = "created_at"
      type = "string"
    }
  }
}

# ────────────────────────────────────────────────────────────────────────────
# OPTIONAL CRAWLERS (disabled by default to save cost)
# Set var.enable_crawler = true to activate.
# ────────────────────────────────────────────────────────────────────────────
resource "aws_glue_crawler" "dwh" {
  for_each = var.enable_crawler ? toset(local.tables) : toset([])

  name          = "${var.environment}-${each.key}-crawler"
  role          = var.glue_etl_role_arn
  database_name = aws_glue_catalog_database.dwh.name

  delta_target {
    delta_tables              = ["s3://${var.dwh_bucket_id}/dwh/${each.key}/"]
    write_manifest            = false
    create_native_delta_table = true
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-${each.key}-crawler" })
}
