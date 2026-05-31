"""
Generate dirty versions of the three source CSVs for pipeline testing.

Dirty transformations applied per file:
  - 5%  null primary-key rows  (product_id / order_id / id)
  - 5%  full-row duplicates
  - 2%  rows with orphan order_id in order_items (not present in orders)
  - 2%  rows with bad order_timestamp ("not-a-date") in orders / order_items
  - Output written to DATA_DIR/dirty/

Usage:
    python generate_dirty_data.py [--data-dir PATH] [--seed INT]
"""

import argparse
import csv
import os
import random
import sys
from typing import List

DEFAULT_DATA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data"
)

PRODUCTS_FILE = "products.csv"
ORDERS_FILE = "orders_apr_2025.csv"
ORDER_ITEMS_FILE = "order_items_apr_2025.csv"

DIRTY_PRODUCTS_FILE = "dirty_products.csv"
DIRTY_ORDERS_FILE = "dirty_orders.csv"
DIRTY_ORDER_ITEMS_FILE = "dirty_order_items.csv"

NULL_KEY_RATE = 0.05
DUPLICATE_RATE = 0.05
ORPHAN_RATE = 0.02
BAD_DATE_RATE = 0.02

ORPHAN_ORDER_ID = "ORD-ORPHAN-99999999"
BAD_DATE_VALUE = "not-a-date"


def read_csv(path: str) -> tuple[List[str], List[List[str]]]:
    """Return (headers, data_rows) from a CSV file."""
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        headers = next(reader)
        rows = [row for row in reader]
    return headers, rows


def write_csv(path: str, headers: List[str], rows: List[List[str]]) -> int:
    """Write rows to CSV. Returns number of data rows written."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(headers)
        writer.writerows(rows)
    return len(rows)


def inject_null_key(rows: List[List[str]], key_col_idx: int, rate: float, rng: random.Random) -> List[List[str]]:
    """Replace the key column value with empty string for ~rate fraction of rows."""
    result = []
    for row in rows:
        if rng.random() < rate:
            row = list(row)
            row[key_col_idx] = ""
        result.append(row)
    return result


def inject_duplicates(rows: List[List[str]], rate: float, rng: random.Random) -> List[List[str]]:
    """Append full-row duplicates for ~rate fraction of randomly sampled rows."""
    n = max(1, int(len(rows) * rate))
    dupes = [list(rng.choice(rows)) for _ in range(n)]
    combined = list(rows) + dupes
    rng.shuffle(combined)
    return combined


def inject_bad_dates(rows: List[List[str]], date_col_idx: int, rate: float, rng: random.Random) -> List[List[str]]:
    """Replace the timestamp column value with BAD_DATE_VALUE for ~rate fraction of rows."""
    result = []
    for row in rows:
        if rng.random() < rate:
            row = list(row)
            row[date_col_idx] = BAD_DATE_VALUE
        result.append(row)
    return result


def inject_orphan_order_ids(
    rows: List[List[str]],
    order_id_col_idx: int,
    rate: float,
    rng: random.Random,
) -> List[List[str]]:
    """Replace order_id with a synthetic orphan value for ~rate fraction of rows."""
    result = []
    for row in rows:
        if rng.random() < rate:
            row = list(row)
            row[order_id_col_idx] = ORPHAN_ORDER_ID
        result.append(row)
    return result


def col_index(headers: List[str], name: str) -> int:
    """Return the index of a column by name (case-insensitive). Raises if not found."""
    lower = [h.lower() for h in headers]
    try:
        return lower.index(name.lower())
    except ValueError:
        raise ValueError(f"Column '{name}' not found in headers: {headers}") from None


def dirty_products(data_dir: str, dirty_dir: str, rng: random.Random) -> None:
    src = os.path.join(data_dir, PRODUCTS_FILE)
    dst = os.path.join(dirty_dir, DIRTY_PRODUCTS_FILE)

    headers, rows = read_csv(src)
    key_idx = col_index(headers, "product_id")

    rows = inject_null_key(rows, key_idx, NULL_KEY_RATE, rng)
    rows = inject_duplicates(rows, DUPLICATE_RATE, rng)

    n = write_csv(dst, headers, rows)
    print(f"  dirty_products.csv : {n} rows -> {dst}")


def dirty_orders(data_dir: str, dirty_dir: str, rng: random.Random) -> None:
    src = os.path.join(data_dir, ORDERS_FILE)
    dst = os.path.join(dirty_dir, DIRTY_ORDERS_FILE)

    headers, rows = read_csv(src)
    key_idx = col_index(headers, "order_id")

    # Find order_timestamp column — tolerate missing column gracefully
    try:
        ts_idx = col_index(headers, "order_timestamp")
        has_ts = True
    except ValueError:
        has_ts = False
        print(
            "  WARNING: 'order_timestamp' column not found in orders; skipping bad-date injection.",
            file=sys.stderr,
        )

    rows = inject_null_key(rows, key_idx, NULL_KEY_RATE, rng)
    rows = inject_duplicates(rows, DUPLICATE_RATE, rng)
    if has_ts:
        rows = inject_bad_dates(rows, ts_idx, BAD_DATE_RATE, rng)

    n = write_csv(dst, headers, rows)
    print(f"  dirty_orders.csv   : {n} rows -> {dst}")


def dirty_order_items(data_dir: str, dirty_dir: str, rng: random.Random) -> None:
    src = os.path.join(data_dir, ORDER_ITEMS_FILE)
    dst = os.path.join(dirty_dir, DIRTY_ORDER_ITEMS_FILE)

    headers, rows = read_csv(src)
    key_idx = col_index(headers, "id")
    order_id_idx = col_index(headers, "order_id")

    try:
        ts_idx = col_index(headers, "order_timestamp")
        has_ts = True
    except ValueError:
        has_ts = False

    rows = inject_null_key(rows, key_idx, NULL_KEY_RATE, rng)
    rows = inject_duplicates(rows, DUPLICATE_RATE, rng)
    rows = inject_orphan_order_ids(rows, order_id_idx, ORPHAN_RATE, rng)
    if has_ts:
        rows = inject_bad_dates(rows, ts_idx, BAD_DATE_RATE, rng)

    n = write_csv(dst, headers, rows)
    print(f"  dirty_order_items.csv : {n} rows -> {dst}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate dirty CSV data for pipeline integration tests."
    )
    parser.add_argument(
        "--data-dir",
        default=DEFAULT_DATA_DIR,
        help=f"Directory containing source CSVs (default: {DEFAULT_DATA_DIR})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)",
    )
    args = parser.parse_args()

    data_dir = os.path.abspath(args.data_dir)
    if not os.path.isdir(data_dir):
        print(f"ERROR: data directory not found: {data_dir}", file=sys.stderr)
        sys.exit(1)

    dirty_dir = os.path.join(data_dir, "dirty")
    os.makedirs(dirty_dir, exist_ok=True)

    rng = random.Random(args.seed)

    print(f"Generating dirty data (seed={args.seed}) ...")

    for fname, label in [
        (PRODUCTS_FILE, "products"),
        (ORDERS_FILE, "orders"),
        (ORDER_ITEMS_FILE, "order_items"),
    ]:
        if not os.path.isfile(os.path.join(data_dir, fname)):
            print(
                f"  WARNING: source file not found, skipping {label}: {os.path.join(data_dir, fname)}",
                file=sys.stderr,
            )

    if os.path.isfile(os.path.join(data_dir, PRODUCTS_FILE)):
        dirty_products(data_dir, dirty_dir, rng)
    if os.path.isfile(os.path.join(data_dir, ORDERS_FILE)):
        dirty_orders(data_dir, dirty_dir, rng)
    if os.path.isfile(os.path.join(data_dir, ORDER_ITEMS_FILE)):
        dirty_order_items(data_dir, dirty_dir, rng)

    print("Done.")


if __name__ == "__main__":
    main()
