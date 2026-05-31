"""
Convert orders_apr_2025.xlsx and order_items_apr_2025.xlsx to CSV files.

Usage:
    python convert_xlsx_to_csv.py [--data-dir PATH]

The script reads both XLSX files from DATA_DIR and writes CSV files to the
same directory. products.csv is expected to already exist.
"""

import argparse
import csv
import os
import sys

import openpyxl


DEFAULT_DATA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data"
)

XLSX_FILES = {
    "orders_apr_2025.xlsx": "orders_apr_2025.csv",
    "order_items_apr_2025.xlsx": "order_items_apr_2025.csv",
}


def xlsx_to_csv(xlsx_path: str, csv_path: str) -> int:
    """Convert a single XLSX file to CSV. Returns the number of data rows written."""
    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active

    rows_written = 0
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        for i, row in enumerate(ws.iter_rows(values_only=True)):
            # Skip completely empty rows
            if all(cell is None for cell in row):
                continue
            writer.writerow(["" if cell is None else cell for cell in row])
            if i > 0:
                rows_written += 1

    wb.close()
    return rows_written


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert orders/order_items XLSX files to CSV."
    )
    parser.add_argument(
        "--data-dir",
        default=DEFAULT_DATA_DIR,
        help=f"Directory containing XLSX files (default: {DEFAULT_DATA_DIR})",
    )
    args = parser.parse_args()

    data_dir = os.path.abspath(args.data_dir)
    if not os.path.isdir(data_dir):
        print(f"ERROR: data directory not found: {data_dir}", file=sys.stderr)
        sys.exit(1)

    for xlsx_name, csv_name in XLSX_FILES.items():
        xlsx_path = os.path.join(data_dir, xlsx_name)
        csv_path = os.path.join(data_dir, csv_name)

        if not os.path.isfile(xlsx_path):
            print(f"WARNING: XLSX file not found, skipping: {xlsx_path}", file=sys.stderr)
            continue

        print(f"Converting {xlsx_name} -> {csv_name} ...", end=" ", flush=True)
        n = xlsx_to_csv(xlsx_path, csv_path)
        print(f"{n} rows written to {csv_path}")

    print("Done.")


if __name__ == "__main__":
    main()
