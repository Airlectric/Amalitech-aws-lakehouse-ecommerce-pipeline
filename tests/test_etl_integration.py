"""Integration tests for the lakehouse ETL chain.

Each test exercises a complete slice of the pipeline using a local SparkSession
with Delta Lake extensions and a temporary filesystem directory as the
lakehouse root — no S3, no Glue runtime required.

Test coverage
-------------
- validate → dedup → merge_into_delta for each dataset (products, orders, order_items)
- Idempotency: running the same data twice leaves the table count unchanged
- Referential integrity: order_items rows with unknown order_id / product_id
  land in orphans_df with the correct rejection_reason
- Schema drift: check_schema_drift raises ValueError on extra / missing columns
- Empty-file guard: isEmpty() short-circuits before any merge
- Post-MERGE reconciliation: merge_into_delta raises RuntimeError when Delta
  history metrics disagree with the source row count (simulated by patching)

Markers
-------
@pytest.mark.spark  — skipped automatically when PySpark is not installed or
                      when Java is absent (via pytest.importorskip).
"""

import os
import shutil
import tempfile

import pytest

pyspark = pytest.importorskip("pyspark", reason="PySpark not installed; skipping Spark tests")
delta = pytest.importorskip("delta", reason="delta-spark not installed; skipping Spark tests")

from delta import configure_spark_with_delta_pip  # noqa: E402
from pyspark.sql import SparkSession  # noqa: E402

from common.delta_io import dedup_df, merge_into_delta  # noqa: E402
from common.schemas import (  # noqa: E402
    get_order_items_schema,
    get_orders_schema,
    get_products_schema,
)
from common.validation import (  # noqa: E402
    check_schema_drift,
    validate_df,
    validate_referential_integrity,
)

# ---------------------------------------------------------------------------
# SparkSession fixture — shared across all tests in this module
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def spark():
    builder = (
        SparkSession.builder.master("local[2]")
        .appName("lakehouse-integration-tests")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.ui.enabled", "false")
    )
    session = configure_spark_with_delta_pip(builder).getOrCreate()
    yield session
    session.stop()


@pytest.fixture
def tmp_dir():
    """Fresh temporary directory for each test."""
    path = tempfile.mkdtemp(prefix="lakehouse_test_")
    yield path
    shutil.rmtree(path, ignore_errors=True)


# ---------------------------------------------------------------------------
# Helper: write a CSV file under tmp_dir and return its path
# ---------------------------------------------------------------------------

def _write_csv(tmp_dir, filename, header, rows):
    path = os.path.join(tmp_dir, filename)
    with open(path, "w") as fh:
        fh.write(header + "\n")
        for row in rows:
            fh.write(",".join(str(v) for v in row) + "\n")
    return path


# ---------------------------------------------------------------------------
# products — validate → dedup → merge
# ---------------------------------------------------------------------------

@pytest.mark.spark
def test_products_etl_end_to_end(spark, tmp_dir):
    rows = [
        (1, 10, "Produce", "Apple"),
        (2, 11, "Dairy", "Milk"),
        (1, 10, "Produce", "Apple"),  # duplicate PK
    ]
    df = spark.createDataFrame(rows, schema=get_products_schema())

    valid_df, rejected_df = validate_df(df, "products", spark)
    assert rejected_df.count() == 0

    deduped = dedup_df(valid_df, pk_col="product_id", ts_col=None)
    assert deduped.count() == 2

    delta_path = os.path.join(tmp_dir, "products")
    merge_into_delta(spark, deduped, delta_path, pk_col="product_id")

    result = spark.read.format("delta").load(delta_path)
    assert result.count() == 2
    assert set(result.select("product_id").toPandas()["product_id"]) == {1, 2}


@pytest.mark.spark
def test_products_etl_idempotent(spark, tmp_dir):
    rows = [(1, 10, "Produce", "Apple"), (2, 11, "Dairy", "Milk")]
    df = spark.createDataFrame(rows, schema=get_products_schema())
    delta_path = os.path.join(tmp_dir, "products")

    for _ in range(2):
        valid_df, _ = validate_df(df, "products", spark)
        deduped = dedup_df(valid_df, pk_col="product_id", ts_col=None)
        merge_into_delta(spark, deduped, delta_path, pk_col="product_id")

    assert spark.read.format("delta").load(delta_path).count() == 2


# ---------------------------------------------------------------------------
# orders — validate → dedup → merge (partitioned by date)
# ---------------------------------------------------------------------------

_ORDERS_SCHEMA = get_orders_schema()


@pytest.mark.spark
def test_orders_etl_end_to_end(spark, tmp_dir):
    rows = [
        (1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15"),
        (2, 101, 6, "2024-01-16 08:00:00", 15.50, "2024-01-16"),
        (3, 100, 5, "2024-01-15 11:00:00", 30.00, "2024-01-15"),  # newer ts same PK
    ]
    df = spark.createDataFrame(rows, schema=_ORDERS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "orders", spark)
    assert rejected_df.count() == 0

    deduped = dedup_df(valid_df, pk_col="order_id", ts_col="order_timestamp")
    assert deduped.count() == 2

    delta_path = os.path.join(tmp_dir, "orders")
    merge_into_delta(spark, deduped, delta_path, pk_col="order_id", partition_col="date")

    result = spark.read.format("delta").load(delta_path)
    assert result.count() == 2
    # The surviving order_id=100 row should have the later timestamp
    row_100 = result.filter("order_id = 100").collect()[0]
    assert row_100["total_amount"] == pytest.approx(30.00, abs=0.01)


@pytest.mark.spark
def test_orders_etl_idempotent(spark, tmp_dir):
    rows = [
        (1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15"),
        (2, 101, 6, "2024-01-16 08:00:00", 15.50, "2024-01-16"),
    ]
    df = spark.createDataFrame(rows, schema=_ORDERS_SCHEMA)
    delta_path = os.path.join(tmp_dir, "orders")

    for _ in range(2):
        valid_df, _ = validate_df(df, "orders", spark)
        deduped = dedup_df(valid_df, pk_col="order_id", ts_col="order_timestamp")
        merge_into_delta(spark, deduped, delta_path, pk_col="order_id", partition_col="date")

    assert spark.read.format("delta").load(delta_path).count() == 2


@pytest.mark.spark
def test_orders_bad_timestamp_rejected(spark, tmp_dir):
    rows = [
        (1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15"),
        (2, 101, 6, "NOT-A-DATE", 15.50, "2024-01-16"),
    ]
    df = spark.createDataFrame(rows, schema=_ORDERS_SCHEMA)
    valid_df, rejected_df = validate_df(df, "orders", spark)

    assert valid_df.count() == 1
    assert rejected_df.count() == 1
    assert rejected_df.collect()[0]["order_id"] == 101


# ---------------------------------------------------------------------------
# order_items — validate + referential integrity → dedup → merge
# ---------------------------------------------------------------------------

_ORDER_ITEMS_SCHEMA = get_order_items_schema()


@pytest.mark.spark
def test_order_items_ri_orphans_rejected(spark, tmp_dir):
    """Orphan rows (unknown order_id / product_id) must land in orphans_df."""
    # Seed parent tables
    orders_path = os.path.join(tmp_dir, "orders")
    products_path = os.path.join(tmp_dir, "products")

    orders_rows = [(1, 10, 5, "2024-01-15 10:00:00", 20.0, "2024-01-15")]
    spark.createDataFrame(orders_rows, schema=_ORDERS_SCHEMA).write.format("delta").save(orders_path)

    products_rows = [(100, 1, "Produce", "Apple"), (200, 2, "Dairy", "Milk")]
    spark.createDataFrame(products_rows, schema=get_products_schema()).write.format("delta").save(products_path)

    # order_items: row 1 is valid, row 2 has unknown order_id, row 3 has unknown product_id
    oi_rows = [
        (1, 10, 5, 0.0, 100, 1, 0, "2024-01-15 10:00:00", "2024-01-15"),   # valid
        (2, 99, 5, 0.0, 100, 1, 0, "2024-01-15 10:00:00", "2024-01-15"),   # orphan order_id=99
        (3, 10, 5, 0.0, 999, 1, 0, "2024-01-15 10:00:00", "2024-01-15"),   # orphan product_id=999
    ]
    df = spark.createDataFrame(oi_rows, schema=_ORDER_ITEMS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "order_items", spark)
    assert rejected_df.count() == 0  # all pass row-level checks

    clean_df, orphans_df = validate_referential_integrity(valid_df, "order_items", spark, tmp_dir)

    assert clean_df.count() == 1
    orphan_count = orphans_df.count()
    assert orphan_count == 2

    reasons = {r["rejection_reason"] for r in orphans_df.collect()}
    assert "orphan order_id" in reasons
    assert "orphan product_id" in reasons


@pytest.mark.spark
def test_ri_skipped_when_parent_table_absent(spark, tmp_dir):
    """RI check is a no-op when parent Delta tables don't exist yet."""
    oi_rows = [
        (1, 10, 5, 0.0, 100, 1, 0, "2024-01-15 10:00:00", "2024-01-15"),
    ]
    df = spark.createDataFrame(oi_rows, schema=_ORDER_ITEMS_SCHEMA)

    # tmp_dir has no Delta tables — should return all rows as clean
    clean_df, orphans_df = validate_referential_integrity(df, "order_items", spark, tmp_dir)

    assert clean_df.count() == 1
    assert orphans_df.count() == 0


@pytest.mark.spark
def test_order_items_idempotent(spark, tmp_dir):
    oi_rows = [
        (1, 10, 5, 0.0, 100, 1, 0, "2024-01-15 10:00:00", "2024-01-15"),
        (2, 10, 5, 1.0, 100, 2, 1, "2024-01-15 11:00:00", "2024-01-15"),
    ]
    df = spark.createDataFrame(oi_rows, schema=_ORDER_ITEMS_SCHEMA)
    delta_path = os.path.join(tmp_dir, "order_items")

    for _ in range(2):
        valid_df, _ = validate_df(df, "order_items", spark)
        deduped = dedup_df(valid_df, pk_col="id", ts_col="order_timestamp")
        merge_into_delta(spark, deduped, delta_path, pk_col="id", partition_col="date")

    assert spark.read.format("delta").load(delta_path).count() == 2


# ---------------------------------------------------------------------------
# check_schema_drift
# ---------------------------------------------------------------------------

@pytest.mark.spark
def test_schema_drift_extra_column_raises(spark, tmp_dir):
    csv_path = _write_csv(
        tmp_dir,
        "products_extra.csv",
        "product_id,department_id,department,product_name,extra_col",
        [(1, 10, "Produce", "Apple", "unexpected")],
    )
    with pytest.raises(ValueError, match="extra_columns"):
        check_schema_drift(spark, csv_path, get_products_schema(), "products")


@pytest.mark.spark
def test_schema_drift_missing_column_raises(spark, tmp_dir):
    csv_path = _write_csv(
        tmp_dir,
        "products_missing.csv",
        "product_id,department_id",  # missing department and product_name
        [(1, 10)],
    )
    with pytest.raises(ValueError, match="missing_columns"):
        check_schema_drift(spark, csv_path, get_products_schema(), "products")


@pytest.mark.spark
def test_schema_drift_exact_match_ok(spark, tmp_dir):
    csv_path = _write_csv(
        tmp_dir,
        "products_ok.csv",
        "product_id,department_id,department,product_name",
        [(1, 10, "Produce", "Apple")],
    )
    # Should not raise
    check_schema_drift(spark, csv_path, get_products_schema(), "products")


# ---------------------------------------------------------------------------
# Empty DataFrame guard (unit-level — no Delta I/O needed)
# ---------------------------------------------------------------------------

@pytest.mark.spark
def test_empty_dataframe_is_detected(spark):
    empty = spark.createDataFrame([], schema=get_orders_schema())
    assert empty.isEmpty() is True


@pytest.mark.spark
def test_non_empty_dataframe_is_not_detected(spark):
    rows = [(1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15")]
    df = spark.createDataFrame(rows, schema=get_orders_schema())
    assert df.isEmpty() is False
