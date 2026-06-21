"""maintenance_etl.py — Delta Lake OPTIMIZE + VACUUM job.

Runs compaction (OPTIMIZE) then removes files beyond the retention window
(VACUUM) for each of the three lakehouse Delta tables. Scheduled by
EventBridge Scheduler to run daily (default: 02:00 UTC) so small-file
accumulation and historical-version bloat are bounded automatically.

Job arguments
-------------
--dwh_path            : S3 URI base path of the lakehouse (e.g. s3://my-dw/dwh).
--vacuum_retain_hours : Minimum file-age in hours to retain (default: 168 = 7 days).
                        Delta requires this to be ≥ 168 unless the safety check is
                        disabled — do not lower below 168 in production.
"""

import sys

from pyspark.sql import SparkSession

_TABLES = ["products", "orders", "order_items"]


def _optimize_and_vacuum(spark: SparkSession, table_path: str, retain_hours: int) -> None:
    """Run OPTIMIZE then VACUUM on a single Delta table."""
    from delta.tables import DeltaTable

    if not DeltaTable.isDeltaTable(spark, table_path):
        print(f"[maintenance] {table_path} is not a Delta table; skipping.")
        return

    print(f"[maintenance] OPTIMIZE {table_path}")
    spark.sql(f"OPTIMIZE delta.`{table_path}`")

    print(f"[maintenance] VACUUM {table_path} RETAIN {retain_hours} HOURS")
    DeltaTable.forPath(spark, table_path).vacuum(retain_hours)

    print(f"[maintenance] Done: {table_path}")


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(
        sys.argv,
        ["dwh_path", "vacuum_retain_hours"],
    )

    dwh_path = args["dwh_path"].rstrip("/")
    retain_hours = int(args["vacuum_retain_hours"])

    spark = (
        SparkSession.builder.appName("DeltaMaintenanceETL")
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

    # Allow VACUUM below the default 7-day safety floor only when explicitly
    # overridden. In production retain_hours should always be >= 168.
    if retain_hours < 168:
        spark.conf.set("spark.databricks.delta.retentionDurationCheck.enabled", "false")

    print(f"[maintenance] Starting Delta maintenance: retain_hours={retain_hours}")
    for table in _TABLES:
        _optimize_and_vacuum(spark, f"{dwh_path}/{table}", retain_hours)

    print("[maintenance] All tables maintained successfully.")
    spark.stop()


if __name__ == "__main__":
    main()
