"""Tests for glue/common/validation.py.

Strategy
--------
Running a full SparkSession in CI is heavy.  These tests therefore use a
local[1] SparkSession when PySpark is available (marked ``@pytest.mark.slow``
so they can be skipped in quick-feedback runs with ``-m "not slow"``).

When PySpark is not installed the tests are automatically skipped via the
module-level ``pytest.importorskip`` call so the suite remains green in
environments that only have the lightweight dependencies installed.
"""

import pytest

pyspark = pytest.importorskip("pyspark", reason="PySpark not installed; skipping Spark tests")

from pyspark.sql import SparkSession  # noqa: E402
from pyspark.sql.types import (  # noqa: E402
    FloatType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

# validation module is added to sys.path by conftest.py (via the glue/ dir).
from common.validation import validate_df  # noqa: E402


# ---------------------------------------------------------------------------
# Session-scoped SparkSession shared across all slow tests in this module
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def spark():
    """Lightweight local[1] SparkSession for unit testing."""
    session = (
        SparkSession.builder
        .master("local[1]")
        .appName("lakehouse-validation-tests")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield session
    session.stop()


# ---------------------------------------------------------------------------
# Schema helpers
# ---------------------------------------------------------------------------

_PRODUCTS_SCHEMA = StructType(
    [
        StructField("product_id", IntegerType(), True),
        StructField("department_id", IntegerType(), True),
        StructField("department", StringType(), True),
        StructField("product_name", StringType(), True),
    ]
)

_ORDERS_SCHEMA = StructType(
    [
        StructField("order_num", IntegerType(), True),
        StructField("order_id", IntegerType(), True),
        StructField("user_id", IntegerType(), True),
        StructField("order_timestamp", StringType(), True),
        StructField("total_amount", FloatType(), True),
        StructField("date", StringType(), True),
    ]
)

_ORDER_ITEMS_SCHEMA = StructType(
    [
        StructField("id", IntegerType(), True),
        StructField("order_id", IntegerType(), True),
        StructField("user_id", IntegerType(), True),
        StructField("days_since_prior_order", FloatType(), True),
        StructField("product_id", IntegerType(), True),
        StructField("add_to_cart_order", IntegerType(), True),
        StructField("reordered", IntegerType(), True),
        StructField("order_timestamp", StringType(), True),
        StructField("date", StringType(), True),
    ]
)


# ---------------------------------------------------------------------------
# Tests — products dataset
# ---------------------------------------------------------------------------

@pytest.mark.slow
def test_null_product_id_rejected(spark):
    """Rows with a null product_id must land in rejected_df, not valid_df."""
    rows = [
        (1, 10, "Produce", "Apple"),
        (None, 11, "Dairy", "Milk"),  # null PK — should be rejected
        (3, 12, "Bakery", "Bread"),
    ]
    df = spark.createDataFrame(rows, schema=_PRODUCTS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "products", spark)

    assert valid_df.count() == 2
    assert rejected_df.count() == 1
    assert rejected_df.collect()[0]["product_id"] is None


@pytest.mark.slow
def test_valid_products_all_kept(spark):
    """All rows with non-null product_id must pass validation unchanged."""
    rows = [
        (1, 10, "Produce", "Apple"),
        (2, 11, "Dairy", "Milk"),
    ]
    df = spark.createDataFrame(rows, schema=_PRODUCTS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "products", spark)

    assert valid_df.count() == 2
    assert rejected_df.count() == 0


# ---------------------------------------------------------------------------
# Tests — orders dataset
# ---------------------------------------------------------------------------

@pytest.mark.slow
def test_bad_timestamp_rejected_for_orders(spark):
    """Rows with an unparseable order_timestamp string must be rejected."""
    rows = [
        (1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15"),   # valid
        (2, 101, 6, "not-a-timestamp", 15.50, "2024-01-16"),        # bad ts
    ]
    df = spark.createDataFrame(rows, schema=_ORDERS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "orders", spark)

    assert valid_df.count() == 1
    assert rejected_df.count() == 1
    assert rejected_df.collect()[0]["order_id"] == 101


@pytest.mark.slow
def test_valid_orders_all_kept(spark):
    """Well-formed orders rows must all pass validation."""
    rows = [
        (1, 100, 5, "2024-01-15 10:30:00", 29.99, "2024-01-15"),
        (2, 101, 6, "2024-01-16 08:00:00", 15.50, "2024-01-16"),
    ]
    df = spark.createDataFrame(rows, schema=_ORDERS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "orders", spark)

    assert valid_df.count() == 2
    assert rejected_df.count() == 0


# ---------------------------------------------------------------------------
# Tests — order_items dataset
# ---------------------------------------------------------------------------

@pytest.mark.slow
def test_reordered_2_rejected_for_order_items(spark):
    """Rows where reordered=2 (not in (0,1)) must be rejected."""
    rows = [
        (1, 200, 5, 3.0, 10, 1, 0, "2024-01-15 10:30:00", "2024-01-15"),  # valid
        (2, 201, 6, 0.0, 11, 2, 1, "2024-01-15 11:00:00", "2024-01-15"),  # valid
        (3, 202, 7, 1.0, 12, 3, 2, "2024-01-15 12:00:00", "2024-01-15"),  # bad reordered
    ]
    df = spark.createDataFrame(rows, schema=_ORDER_ITEMS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "order_items", spark)

    assert valid_df.count() == 2
    assert rejected_df.count() == 1
    assert rejected_df.collect()[0]["id"] == 3


@pytest.mark.slow
def test_null_pk_rejected_for_order_items(spark):
    """Rows with a null id (PK) must be rejected in order_items."""
    rows = [
        (1, 200, 5, 3.0, 10, 1, 0, "2024-01-15 10:30:00", "2024-01-15"),  # valid
        (None, 201, 6, 0.0, 11, 2, 1, "2024-01-15 11:00:00", "2024-01-15"),  # null PK
    ]
    df = spark.createDataFrame(rows, schema=_ORDER_ITEMS_SCHEMA)

    valid_df, rejected_df = validate_df(df, "order_items", spark)

    assert valid_df.count() == 1
    assert rejected_df.count() == 1


@pytest.mark.slow
def test_unknown_dataset_raises(spark):
    """validate_df must raise ValueError for an unrecognised dataset name."""
    rows = [(1, "x")]
    schema = StructType(
        [StructField("id", IntegerType(), True), StructField("name", StringType(), True)]
    )
    df = spark.createDataFrame(rows, schema=schema)

    with pytest.raises(ValueError, match="Unknown dataset"):
        validate_df(df, "unknown_dataset", spark)
