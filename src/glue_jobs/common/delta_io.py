from datetime import date

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql import Window


def dedup_df(
    df: DataFrame,
    pk_col: str,
    ts_col: str = "order_timestamp",
) -> DataFrame:
    """Return a deduplicated DataFrame keeping the latest row per primary key.

    When *ts_col* is supplied (non-None / non-empty), the function uses a
    window function (row_number ordered by *ts_col* DESC) so that the most
    recently timestamped version of each key survives.

    When *ts_col* is None or an empty string, plain ``dropDuplicates([pk_col])``
    is used instead (appropriate for dimension tables without a change timestamp,
    such as products).

    Parameters
    ----------
    df     : source DataFrame.
    pk_col : primary-key column name used to define uniqueness.
    ts_col : ordering column for tie-breaking; pass None or "" for dimensions.

    Returns
    -------
    DataFrame with at most one row per *pk_col* value.
    """
    if not ts_col:
        deduped = df.dropDuplicates([pk_col])
        print(f"[dedup] pk={pk_col} strategy=dropDuplicates rows={deduped.count()}")
        return deduped

    window = Window.partitionBy(pk_col).orderBy(F.col(ts_col).desc())
    deduped = (
        df.withColumn("_rn", F.row_number().over(window))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
    )
    print(f"[dedup] pk={pk_col} ts_col={ts_col} strategy=row_number rows={deduped.count()}")
    return deduped


def merge_into_delta(
    spark: SparkSession,
    source_df: DataFrame,
    target_path: str,
    pk_col: str,
    partition_col: str = None,
) -> None:
    """Upsert *source_df* into a Delta table at *target_path*.

    Behaviour
    ---------
    - If *target_path* already contains a Delta table, performs a MERGE INTO
      operation:
        * WHEN MATCHED          -> UPDATE ALL columns from source.
        * WHEN NOT MATCHED      -> INSERT ALL columns from source.
    - If no Delta table exists yet, writes *source_df* as a new Delta table,
      optionally partitioned by *partition_col*.

    Parameters
    ----------
    spark         : active SparkSession.
    source_df     : DataFrame containing the new/updated data.
    target_path   : S3 (or local) path to the Delta table root.
    pk_col        : column used as the join predicate for MERGE.
    partition_col : optional partitioning column for the initial write; ignored
                    on subsequent merges (partitioning is fixed at table creation).
    """
    target_path = target_path.rstrip("/")

    if DeltaTable.isDeltaTable(spark, target_path):
        target_table = DeltaTable.forPath(spark, target_path)
        merge_condition = f"target.{pk_col} = source.{pk_col}"

        (
            target_table.alias("target")
            .merge(source_df.alias("source"), merge_condition)
            .whenMatchedUpdateAll()
            .whenNotMatchedInsertAll()
            .execute()
        )
        print(f"[delta_io] MERGE INTO {target_path} on {pk_col}")
    else:
        writer = source_df.write.format("delta").mode("overwrite")
        if partition_col:
            writer = writer.partitionBy(partition_col)
        writer.save(target_path)
        print(
            f"[delta_io] Initial Delta write to {target_path}"
            + (f" partitioned by {partition_col}" if partition_col else "")
        )


def write_rejected(
    rejected_df: DataFrame,
    rejected_base_path: str,
    dataset_name: str,
) -> None:
    """Persist rejected rows as Parquet under a date-partitioned path.

    Output location
    ---------------
    ``{rejected_base_path}/{dataset_name}/dt={today}/``

    The write uses ``overwrite`` mode so that re-running the same day's job
    replaces the previous rejection file for that partition rather than
    appending duplicates.

    Parameters
    ----------
    rejected_df        : DataFrame of invalid rows (includes ``rejection_reason``).
    rejected_base_path : S3 (or local) base path for rejected data storage.
    dataset_name       : logical name of the dataset (e.g. "products", "orders").
    """
    today_str = date.today().strftime("%Y-%m-%d")
    output_path = f"{rejected_base_path.rstrip('/')}/{dataset_name}/dt={today_str}/"

    rejected_count = rejected_df.count()

    if rejected_count == 0:
        print(f"[delta_io] No rejected rows for {dataset_name} on {today_str}; skipping write.")
        return

    rejected_df.write.mode("overwrite").parquet(output_path)
    print(
        f"[delta_io] Wrote {rejected_count} rejected rows for {dataset_name} "
        f"to {output_path}"
    )
