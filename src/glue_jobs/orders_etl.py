"""orders_etl.py — AWS Glue PySpark job for the orders fact table.

Job arguments (--key value pairs passed via Glue job parameters)
-----------------------------------------------------------------
--raw_bucket   : S3 bucket name that holds the raw CSV landing zone.
--dwh_path     : S3 URI prefix for the Delta lakehouse (e.g. s3://my-dw/delta).
--rejected_path: S3 URI prefix for rejected-row storage (e.g. s3://my-dw/rejected).
--run_date     : Processing date in YYYY-MM-DD format (used for partition filtering
                 and operational logging; the table itself is partitioned by the
                 'date' column derived from order records).

Processing steps
----------------
1. Initialise SparkSession with Delta Lake extensions.
2. Read raw orders CSV from s3://{raw_bucket}/raw/orders/.
3. Validate rows; split into valid / rejected sets.
4. Deduplicate valid rows on order_id ordered by order_timestamp DESC.
5. Merge deduplicated rows into the Delta table at {dwh_path}/orders/,
   partitioned by the 'date' column.
6. Persist rejected rows as Parquet under {rejected_path}/orders/dt={today}/.
7. Stop the SparkSession cleanly.
"""

import sys

from pyspark.sql import SparkSession

from common.delta_io import dedup_df, merge_into_delta, write_rejected
from common.schemas import get_orders_schema
from common.validation import check_schema_drift, validate_df


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(
        sys.argv,
        ["raw_bucket", "dwh_path", "rejected_path", "run_date", "ingested_at", "source_execution_id"],
    )

    raw_bucket = args["raw_bucket"]
    dwh_path = args["dwh_path"].rstrip("/")
    rejected_path = args["rejected_path"].rstrip("/")
    run_date = args["run_date"]
    ingested_at = args["ingested_at"]
    source_execution_id = args["source_execution_id"]

    spark = (
        SparkSession.builder.appName("OrdersETL")
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

    orders_raw_path = f"s3://{raw_bucket}/raw/orders/"
    print(f"[orders_etl] run_date={run_date} Reading raw orders from {orders_raw_path}")

    schema = get_orders_schema()
    check_schema_drift(spark, orders_raw_path, schema, "orders")

    orders_df = (
        spark.read.option("header", "true")
        .schema(schema)
        .csv(orders_raw_path)
    )

    if orders_df.isEmpty():
        print(f"[orders_etl] Source is empty for run_date={run_date}; nothing to merge.")
        spark.stop()
        return

    valid_df, rejected_df = validate_df(orders_df, "orders", spark, run_date=run_date)

    from pyspark.sql import functions as F

    deduped_df = dedup_df(valid_df, pk_col="order_id", ts_col="order_timestamp")
    deduped_df = (
        deduped_df
        .withColumn("ingested_at", F.lit(ingested_at))
        .withColumn("source_execution_id", F.lit(source_execution_id))
    )

    target_delta_path = f"{dwh_path}/orders/"
    merge_into_delta(
        spark,
        deduped_df,
        target_delta_path,
        pk_col="order_id",
        partition_col="date",
    )

    write_rejected(rejected_df, rejected_path, "orders")

    print(f"[orders_etl] Job completed successfully for run_date={run_date}.")
    spark.stop()


if __name__ == "__main__":
    main()
