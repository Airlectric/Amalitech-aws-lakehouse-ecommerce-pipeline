"""products_etl.py — AWS Glue PySpark job for the products dimension table.

Job arguments (--key value pairs passed via Glue job parameters)
-----------------------------------------------------------------
--raw_bucket   : S3 bucket name that holds the raw CSV landing zone.
--dwh_path     : S3 URI prefix for the Delta lakehouse (e.g. s3://my-dw/delta).
--rejected_path: S3 URI prefix for rejected-row storage (e.g. s3://my-dw/rejected).

Processing steps
----------------
1. Initialise SparkSession with Delta Lake extensions.
2. Read raw products CSV from s3://{raw_bucket}/raw/products/.
3. Validate rows; split into valid / rejected sets.
4. Deduplicate valid rows on product_id (no timestamp — dimension table).
5. Merge deduplicated rows into the Delta table at {dwh_path}/products/.
6. Persist rejected rows as Parquet under {rejected_path}/products/dt={today}/.
7. Stop the SparkSession cleanly.
"""

import sys

from pyspark.sql import SparkSession

from common.delta_io import dedup_df, merge_into_delta, write_rejected
from common.schemas import get_products_schema
from common.validation import check_schema_drift, validate_df


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(
        sys.argv,
        ["raw_bucket", "dwh_path", "rejected_path"],
    )

    raw_bucket = args["raw_bucket"]
    dwh_path = args["dwh_path"].rstrip("/")
    rejected_path = args["rejected_path"].rstrip("/")

    spark = (
        SparkSession.builder.appName("ProductsETL")
        .config(
            "spark.sql.extensions",
            "io.delta.sql.DeltaSparkSessionExtension",
        )
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .getOrCreate()
    )

    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

    products_raw_path = f"s3://{raw_bucket}/raw/products/"
    print(f"[products_etl] Reading raw products from {products_raw_path}")

    schema = get_products_schema()
    check_schema_drift(spark, products_raw_path, schema, "products")

    products_df = (
        spark.read.option("header", "true")
        .schema(schema)
        .csv(products_raw_path)
    )

    if products_df.isEmpty():
        print("[products_etl] Source is empty; nothing to merge.")
        spark.stop()
        return

    valid_df, rejected_df = validate_df(products_df, "products", spark, run_date="N/A")

    deduped_df = dedup_df(valid_df, pk_col="product_id", ts_col=None)

    target_delta_path = f"{dwh_path}/products/"
    merge_into_delta(spark, deduped_df, target_delta_path, pk_col="product_id")

    write_rejected(rejected_df, rejected_path, "products")

    print("[products_etl] Job completed successfully.")
    spark.stop()


if __name__ == "__main__":
    main()
