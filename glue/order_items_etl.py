"""order_items_etl.py — AWS Glue PySpark job for the order_items fact table.

Job arguments (--key value pairs passed via Glue job parameters)
-----------------------------------------------------------------
--raw_bucket   : S3 bucket name that holds the raw CSV landing zone.
--dwh_path     : S3 URI prefix for the Delta lakehouse (e.g. s3://my-dw/delta).
--rejected_path: S3 URI prefix for rejected-row storage (e.g. s3://my-dw/rejected).
--run_date     : Processing date in YYYY-MM-DD format (used for operational logging;
                 the table itself is partitioned by the 'date' column derived from
                 order-item records).

Processing steps
----------------
1. Initialise SparkSession with Delta Lake extensions.
2. Read raw order_items CSV from s3://{raw_bucket}/raw/order_items/.
3. Validate rows; split into valid / rejected sets.
4. Deduplicate valid rows on id ordered by order_timestamp DESC.
5. Merge deduplicated rows into the Delta table at {dwh_path}/order_items/,
   partitioned by the 'date' column.
6. Persist rejected rows as Parquet under {rejected_path}/order_items/dt={today}/.
7. Stop the SparkSession cleanly.
"""

import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession

from common.delta_io import dedup_df, merge_into_delta, write_rejected
from common.schemas import get_order_items_schema
from common.validation import validate_df

# ---------------------------------------------------------------------------
# 1. Resolve Glue job arguments
# ---------------------------------------------------------------------------
args = getResolvedOptions(
    sys.argv,
    ["raw_bucket", "dwh_path", "rejected_path", "run_date"],
)

raw_bucket = args["raw_bucket"]
dwh_path = args["dwh_path"].rstrip("/")
rejected_path = args["rejected_path"].rstrip("/")
run_date = args["run_date"]

# ---------------------------------------------------------------------------
# 2. Initialise SparkSession with Delta Lake extensions
# ---------------------------------------------------------------------------
spark = (
    SparkSession.builder.appName("OrderItemsETL")
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

# ---------------------------------------------------------------------------
# 3. Read raw CSV
# ---------------------------------------------------------------------------
order_items_raw_path = f"s3://{raw_bucket}/raw/order_items/"

print(
    f"[order_items_etl] run_date={run_date} "
    f"Reading raw order_items from {order_items_raw_path}"
)

order_items_df = (
    spark.read.option("header", "true")
    .schema(get_order_items_schema())
    .csv(order_items_raw_path)
)

# ---------------------------------------------------------------------------
# 4. Validate
# ---------------------------------------------------------------------------
valid_df, rejected_df = validate_df(order_items_df, "order_items", spark)

# ---------------------------------------------------------------------------
# 5. Deduplicate — keep the row with the most recent order_timestamp per id
# ---------------------------------------------------------------------------
deduped_df = dedup_df(valid_df, pk_col="id", ts_col="order_timestamp")

# ---------------------------------------------------------------------------
# 6. Merge into Delta, partitioned by the 'date' column
# ---------------------------------------------------------------------------
target_delta_path = f"{dwh_path}/order_items/"
merge_into_delta(
    spark,
    deduped_df,
    target_delta_path,
    pk_col="id",
    partition_col="date",
)

# ---------------------------------------------------------------------------
# 7. Persist rejected rows
# ---------------------------------------------------------------------------
write_rejected(rejected_df, rejected_path, "order_items")

# ---------------------------------------------------------------------------
# 8. Done
# ---------------------------------------------------------------------------
print(f"[order_items_etl] Job completed successfully for run_date={run_date}.")
spark.stop()
