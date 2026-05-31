"""Tests for glue/common/schemas.py.

These tests only instantiate the StructType objects and inspect their field
names.  No SparkSession is started — we only use the type-definition classes
from pyspark.sql.types, which are lightweight.  The tests are skipped
automatically when PySpark is not installed.
"""

import pytest

# schemas.py imports pyspark.sql.types at module level.  Skip the whole module
# gracefully when PySpark is not available so the suite stays green in
# environments that only have the lightweight test dependencies installed.
pytest.importorskip("pyspark", reason="PySpark not installed; skipping schema tests")

from common.schemas import get_order_items_schema, get_orders_schema, get_products_schema  # noqa: E402


def _field_names(schema):
    """Return the ordered list of field names from a StructType."""
    return [field.name for field in schema.fields]


# ---------------------------------------------------------------------------
# products schema
# ---------------------------------------------------------------------------

def test_products_schema_fields():
    """get_products_schema() must have exactly the four expected columns in order."""
    expected = ["product_id", "department_id", "department", "product_name"]
    assert _field_names(get_products_schema()) == expected


def test_products_schema_pk_not_nullable():
    """product_id must be declared NOT NULL (the primary key)."""
    schema = get_products_schema()
    pk_field = next(f for f in schema.fields if f.name == "product_id")
    assert pk_field.nullable is False


# ---------------------------------------------------------------------------
# orders schema
# ---------------------------------------------------------------------------

def test_orders_schema_fields():
    """get_orders_schema() must have exactly the six expected columns in order."""
    expected = [
        "order_num",
        "order_id",
        "user_id",
        "order_timestamp",
        "total_amount",
        "date",
    ]
    assert _field_names(get_orders_schema()) == expected


def test_orders_schema_pk_not_nullable():
    """order_id must be declared NOT NULL (the primary key)."""
    schema = get_orders_schema()
    pk_field = next(f for f in schema.fields if f.name == "order_id")
    assert pk_field.nullable is False


# ---------------------------------------------------------------------------
# order_items schema
# ---------------------------------------------------------------------------

def test_order_items_schema_fields():
    """get_order_items_schema() must have exactly the nine expected columns in order."""
    expected = [
        "id",
        "order_id",
        "user_id",
        "days_since_prior_order",
        "product_id",
        "add_to_cart_order",
        "reordered",
        "order_timestamp",
        "date",
    ]
    assert _field_names(get_order_items_schema()) == expected


def test_order_items_schema_pk_not_nullable():
    """id must be declared NOT NULL (the primary key for order_items)."""
    schema = get_order_items_schema()
    pk_field = next(f for f in schema.fields if f.name == "id")
    assert pk_field.nullable is False


# ---------------------------------------------------------------------------
# Type sanity checks (no Spark needed — just inspect the StructField objects)
# ---------------------------------------------------------------------------

def test_products_schema_field_count():
    assert len(get_products_schema().fields) == 4


def test_orders_schema_field_count():
    assert len(get_orders_schema().fields) == 6


def test_order_items_schema_field_count():
    assert len(get_order_items_schema().fields) == 9
