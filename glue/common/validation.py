from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F


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

    return valid_df, rejected_df
