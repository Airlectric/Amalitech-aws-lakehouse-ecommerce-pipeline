from pyspark.sql.types import (
    FloatType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)


def get_products_schema() -> StructType:
    """Explicit schema for the products dimension table.

    Columns
    -------
    product_id   : int  (PK, not nullable)
    department_id: int
    department   : str
    product_name : str
    """
    return StructType(
        [
            StructField("product_id", IntegerType(), False),
            StructField("department_id", IntegerType(), True),
            StructField("department", StringType(), True),
            StructField("product_name", StringType(), True),
        ]
    )


def get_orders_schema() -> StructType:
    """Explicit schema for the orders fact table.

    Columns
    -------
    order_num        : int
    order_id         : int  (PK, not nullable)
    user_id          : int
    order_timestamp  : str  — will be cast to TimestampType during validation
    total_amount     : float
    date             : str  — will be cast to DateType during validation
    """
    return StructType(
        [
            StructField("order_num", IntegerType(), True),
            StructField("order_id", IntegerType(), False),
            StructField("user_id", IntegerType(), True),
            StructField("order_timestamp", StringType(), True),
            StructField("total_amount", FloatType(), True),
            StructField("date", StringType(), True),
        ]
    )


def get_order_items_schema() -> StructType:
    """Explicit schema for the order_items fact table.

    Columns
    -------
    id                     : int  (PK, not nullable)
    order_id               : int
    user_id                : int
    days_since_prior_order : float
    product_id             : int
    add_to_cart_order      : int
    reordered              : int
    order_timestamp        : str  — will be cast to TimestampType during validation
    date                   : str  — will be cast to DateType during validation
    """
    return StructType(
        [
            StructField("id", IntegerType(), False),
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
