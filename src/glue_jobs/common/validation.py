from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructField, StructType


# Sentinel column injected into rejected rows to describe why they were rejected.
_REJECTION_COL = "rejection_reason"

# Datasets that carry timestamp/date string columns requiring parseability checks.
_DATASETS_WITH_TIMESTAMPS = {"orders", "order_items"}

# Primary-key column per dataset.
_PK_MAP = {
    "products": "product_id",
    "orders": "order_id",
    "order_items": "id",
}


def _build_rejection_condition(df: DataFrame, dataset_name: str):
    """Return a Column expression that is True when the row should be rejected,
    together with a human-readable reason string (as a Column literal concat).

    Multiple failure reasons are concatenated with ' | ' so a single pass over
    the data is sufficient.
    """
    pk_col = _PK_MAP[dataset_name]

    # --- null primary key ---
    null_pk = F.col(pk_col).isNull()
    reason_null_pk = F.when(null_pk, F.lit(f"null {pk_col}")).otherwise(F.lit(""))

    reason_parts = [reason_null_pk]
    reject_flag = null_pk

    # --- timestamp / date parseability ---
    if dataset_name in _DATASETS_WITH_TIMESTAMPS:
        # Cast to timestamp; result is null when the string is not parseable.
        ts_invalid = F.to_timestamp(F.col("order_timestamp")).isNull()
        dt_invalid = F.to_date(F.col("date")).isNull()

        reason_ts = F.when(ts_invalid, F.lit("unparseable order_timestamp")).otherwise(
            F.lit("")
        )
        reason_dt = F.when(dt_invalid, F.lit("unparseable date")).otherwise(F.lit(""))

        reason_parts.extend([reason_ts, reason_dt])
        reject_flag = reject_flag | ts_invalid | dt_invalid

    # --- orders-specific: total_amount >= 0 ---
    if dataset_name == "orders":
        negative_amount = F.col("total_amount") < F.lit(0.0)
        reason_amount = F.when(
            negative_amount, F.lit("total_amount < 0")
        ).otherwise(F.lit(""))
        reason_parts.append(reason_amount)
        reject_flag = reject_flag | negative_amount

    # --- order_items-specific: add_to_cart_order >= 0 and reordered in (0, 1) ---
    if dataset_name == "order_items":
        bad_cart = F.col("add_to_cart_order") < F.lit(0)
        bad_reordered = ~F.col("reordered").isin(0, 1)

        reason_cart = F.when(bad_cart, F.lit("add_to_cart_order < 0")).otherwise(
            F.lit("")
        )
        reason_reordered = F.when(
            bad_reordered, F.lit("reordered not in (0,1)")
        ).otherwise(F.lit(""))

        reason_parts.extend([reason_cart, reason_reordered])
        reject_flag = reject_flag | bad_cart | bad_reordered

    # Build the final rejection_reason string by joining non-empty parts with ' | '.
    # We filter empty strings out with array_remove after collecting into an array.
    reason_array = F.array_remove(F.array(*reason_parts), "")
    reason_str = F.array_join(reason_array, " | ")

    return reject_flag, reason_str


def validate_df(
    df: DataFrame,
    dataset_name: str,
    spark: SparkSession,
    run_date: str = "N/A",
):
    """Split *df* into (valid_df, rejected_df) according to dataset-specific rules.

    Validation rules applied
    ------------------------
    All datasets:
        - Primary key column must not be null.

    orders / order_items:
        - order_timestamp string must be parseable as a timestamp (non-null after cast).
        - date string must be parseable as a date (non-null after cast).

    orders only:
        - total_amount must be >= 0.

    order_items only:
        - add_to_cart_order must be >= 0.
        - reordered must be in (0, 1).

    Parameters
    ----------
    df           : input DataFrame (raw, with string columns for timestamps/dates).
    dataset_name : one of "products", "orders", "order_items".
    spark        : active SparkSession (reserved for future use / Glue context).
    run_date     : processing date string (YYYY-MM-DD) used as a CloudWatch dimension.

    Returns
    -------
    (valid_df, rejected_df)
        valid_df    — rows that pass all rules; original columns unchanged.
        rejected_df — rows that fail at least one rule; has an extra column
                      `rejection_reason` (str) describing all failures.
    """
    if dataset_name not in _PK_MAP:
        raise ValueError(
            f"Unknown dataset '{dataset_name}'. Expected one of: {list(_PK_MAP)}"
        )

    reject_flag, reason_str = _build_rejection_condition(df, dataset_name)

    # Rejected rows: attach the reason column.
    rejected_df = (
        df.withColumn(_REJECTION_COL, reason_str)
        .filter(reject_flag)
    )

    # Valid rows: the complement — no extra column added.
    valid_df = df.filter(~reject_flag)

    total_count = df.count()
    valid_count = valid_df.count()
    rejected_count = rejected_df.count()

    print(
        f"[validation] dataset={dataset_name} "
        f"total={total_count} "
        f"valid={valid_count} "
        f"rejected={rejected_count}"
    )

    emit_dq_metrics(dataset_name, run_date, total_count, valid_count, rejected_count)

    return valid_df, rejected_df


def emit_dq_metrics(
    dataset_name: str,
    run_date: str,
    total_count: int,
    valid_count: int,
    rejected_count: int,
) -> None:
    """Publish row-count DQ metrics to CloudWatch (namespace: Lakehouse/DQ).

    Metrics emitted
    ---------------
    TotalRows, ValidRows, RejectedRows, RejectedRatePct

    Dimensions: Dataset=<dataset_name>, RunDate=<run_date>

    Failures are logged and swallowed so a CloudWatch outage never aborts an
    otherwise-healthy ETL job.
    """
    import boto3

    rejected_rate = (rejected_count / total_count * 100.0) if total_count > 0 else 0.0
    dimensions = [
        {"Name": "Dataset", "Value": dataset_name},
        {"Name": "RunDate", "Value": run_date},
    ]
    metric_data = [
        {"MetricName": "TotalRows", "Value": float(total_count), "Unit": "Count", "Dimensions": dimensions},
        {"MetricName": "ValidRows", "Value": float(valid_count), "Unit": "Count", "Dimensions": dimensions},
        {"MetricName": "RejectedRows", "Value": float(rejected_count), "Unit": "Count", "Dimensions": dimensions},
        {"MetricName": "RejectedRatePct", "Value": rejected_rate, "Unit": "Percent", "Dimensions": dimensions},
    ]
    try:
        boto3.client("cloudwatch").put_metric_data(
            Namespace="Lakehouse/DQ",
            MetricData=metric_data,
        )
        print(
            f"[validation] DQ metrics emitted for dataset={dataset_name} run_date={run_date}: "
            f"total={total_count} valid={valid_count} rejected={rejected_count} "
            f"rate={rejected_rate:.1f}%"
        )
    except Exception as exc:  # noqa: BLE001
        print(f"[validation] WARNING: failed to emit DQ metrics ({exc}); continuing.")


def check_schema_drift(
    spark: SparkSession,
    raw_path: str,
    expected_schema,
    dataset_name: str,
) -> None:
    """Raise ValueError if the CSV at raw_path has extra or missing columns.

    Reads only the header row (no schema enforcement) so no full data scan
    is needed. Raises before the main data read so a schema change surfaces
    immediately with a clear error rather than silently null-filling or
    dropping columns.

    Parameters
    ----------
    spark           : active SparkSession.
    raw_path        : S3 (or local) path to the CSV directory or file.
    expected_schema : StructType from common.schemas (defines expected columns).
    dataset_name    : used only for the error message.
    """
    actual_cols = set(spark.read.option("header", "true").csv(raw_path).columns)
    expected_cols = set(expected_schema.fieldNames())
    extra = actual_cols - expected_cols
    missing = expected_cols - actual_cols
    if extra or missing:
        raise ValueError(
            f"[validation] Schema drift for '{dataset_name}': "
            f"extra_columns={sorted(extra) or 'none'}, "
            f"missing_columns={sorted(missing) or 'none'}"
        )
    print(f"[validation] Schema OK for '{dataset_name}': {sorted(actual_cols)}")


def validate_referential_integrity(
    df: DataFrame,
    dataset_name: str,
    spark: SparkSession,
    dwh_path: str,
) -> tuple:
    """Anti-join order_items rows against parent Delta tables; return (clean_df, orphans_df).

    Only runs for 'order_items'. For every other dataset returns (df, empty_orphans_df)
    immediately. If a parent Delta table has not been created yet (first pipeline run),
    the corresponding FK check is skipped gracefully so the initial load still succeeds.

    FK rules
    --------
    order_items.order_id   must exist in orders.order_id
    order_items.product_id must exist in products.product_id

    Parameters
    ----------
    df           : valid rows produced by validate_df (no rejection_reason column).
    dataset_name : logical dataset name; only 'order_items' triggers RI checks.
    spark        : active SparkSession.
    dwh_path     : S3 (or local) base path of the lakehouse Delta tables.

    Returns
    -------
    (clean_df, orphans_df)
        clean_df   — rows that pass all FK checks; no rejection_reason column.
        orphans_df — rows that failed at least one FK check; has rejection_reason column.
    """
    from delta.tables import DeltaTable

    _empty_orphans = spark.createDataFrame(
        [],
        StructType(list(df.schema.fields) + [StructField(_REJECTION_COL, StringType(), True)]),
    )

    if dataset_name != "order_items":
        return df, _empty_orphans

    dwh_path = dwh_path.rstrip("/")
    clean_df = df
    orphan_frames = []

    for fk_col, parent_table, parent_pk in (
        ("order_id", "orders", "order_id"),
        ("product_id", "products", "product_id"),
    ):
        parent_path = f"{dwh_path}/{parent_table}"
        if not DeltaTable.isDeltaTable(spark, parent_path):
            print(
                f"[validation] RI: {parent_path} not found; "
                f"skipping {fk_col} FK check on first run"
            )
            continue

        parent_pks = (
            spark.read.format("delta").load(parent_path).select(parent_pk).distinct()
        )
        orphans = clean_df.join(parent_pks, on=fk_col, how="left_anti").withColumn(
            _REJECTION_COL, F.lit(f"orphan {fk_col}")
        )
        orphan_frames.append(orphans)
        clean_df = clean_df.join(parent_pks, on=fk_col, how="inner")

    if not orphan_frames:
        return clean_df, _empty_orphans

    orphans_df = orphan_frames[0]
    for frame in orphan_frames[1:]:
        orphans_df = orphans_df.union(frame)

    print(f"[validation] RI check complete for '{dataset_name}'")
    return clean_df, orphans_df
