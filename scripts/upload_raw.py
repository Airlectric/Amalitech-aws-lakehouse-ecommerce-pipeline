"""
Upload raw CSV files from Data/ to S3 under the raw/ prefix.

S3 layout produced:
    s3://BUCKET/raw/products/products.csv
    s3://BUCKET/raw/orders/orders_apr_2025.csv
    s3://BUCKET/raw/order_items/order_items_apr_2025.csv

Bucket name is resolved from (in priority order):
  1. --bucket CLI argument
  2. RAW_BUCKET environment variable

Usage:
    python upload_raw.py --bucket MY_BUCKET [--dataset DATASET] [--data-dir PATH]
    python upload_raw.py --bucket MY_BUCKET --data-dir Data/dirty --variant dirty
    RAW_BUCKET=MY_BUCKET python upload_raw.py
"""

import argparse
import os
import sys

import boto3
from botocore.exceptions import BotoCoreError, ClientError

DEFAULT_DATA_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Data"
)

DATASETS = {
    "products": {
        "prefix": "raw/products",
        "clean": "products.csv",
        "dirty": "dirty_products.csv",
    },
    "orders": {
        "prefix": "raw/orders",
        "clean": "orders_apr_2025.csv",
        "dirty": "dirty_orders.csv",
    },
    "order_items": {
        "prefix": "raw/order_items",
        "clean": "order_items_apr_2025.csv",
        "dirty": "dirty_order_items.csv",
    },
}


def resolve_filename(data_dir: str, dataset: str, variant: str) -> str:
    config = DATASETS[dataset]
    if variant != "auto":
        return config[variant]

    clean_path = os.path.join(data_dir, config["clean"])
    dirty_path = os.path.join(data_dir, config["dirty"])
    if os.path.isfile(clean_path):
        return config["clean"]
    if os.path.isfile(dirty_path):
        return config["dirty"]
    return config["clean"]


def selected_datasets(dataset: str) -> list[str]:
    if dataset == "all":
        return list(DATASETS)
    return [dataset]


def upload_file(
    s3_client,
    local_path: str,
    bucket: str,
    s3_key: str,
    dry_run: bool = False,
) -> None:
    if dry_run:
        print(f"  [DRY-RUN] would upload {local_path} -> s3://{bucket}/{s3_key}")
        return

    print(
        f"  Uploading {os.path.basename(local_path)} -> s3://{bucket}/{s3_key} ...",
        end=" ",
        flush=True,
    )
    s3_client.upload_file(local_path, bucket, s3_key)
    print("OK")


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload raw CSV files to S3.")
    parser.add_argument(
        "--bucket",
        default=os.environ.get("RAW_BUCKET"),
        help="Target S3 bucket name (or set RAW_BUCKET env var)",
    )
    parser.add_argument(
        "--data-dir",
        default=DEFAULT_DATA_DIR,
        help=f"Directory containing source CSV files (default: {DEFAULT_DATA_DIR})",
    )
    parser.add_argument(
        "--dataset",
        choices=["all", *DATASETS.keys()],
        default="all",
        help="Dataset to upload (default: all)",
    )
    parser.add_argument(
        "--variant",
        choices=["auto", "clean", "dirty"],
        default="auto",
        help="File naming variant to upload (default: auto)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be uploaded without actually uploading",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_DEFAULT_REGION") or os.environ.get("AWS_REGION", "us-east-1"),
        help="AWS region (default: AWS_DEFAULT_REGION, AWS_REGION, or us-east-1)",
    )
    args = parser.parse_args()

    if not args.bucket:
        print(
            "ERROR: bucket name is required. Pass --bucket or set RAW_BUCKET env var.",
            file=sys.stderr,
        )
        sys.exit(1)

    data_dir = os.path.abspath(args.data_dir)
    if not os.path.isdir(data_dir):
        print(f"ERROR: data directory not found: {data_dir}", file=sys.stderr)
        sys.exit(1)

    s3 = None if args.dry_run else boto3.client("s3", region_name=args.region)
    print(f"Uploading CSVs from {data_dir} to s3://{args.bucket}/raw/ ...")

    errors = []
    uploaded = 0
    for dataset in selected_datasets(args.dataset):
        config = DATASETS[dataset]
        filename = resolve_filename(data_dir, dataset, args.variant)
        local_path = os.path.join(data_dir, filename)
        if not os.path.isfile(local_path):
            print(f"  ERROR: file not found: {local_path}", file=sys.stderr)
            errors.append(filename)
            continue

        s3_key = f"{config['prefix']}/{filename}"
        try:
            upload_file(s3, local_path, args.bucket, s3_key, dry_run=args.dry_run)
            uploaded += 1
        except (BotoCoreError, ClientError) as exc:
            print(f"  ERROR uploading {filename}: {exc}", file=sys.stderr)
            errors.append(filename)

    if errors:
        print(f"\nFailed to upload {len(errors)} file(s): {errors}", file=sys.stderr)
        sys.exit(1)

    if uploaded == 0:
        print("ERROR: no files were uploaded.", file=sys.stderr)
        sys.exit(1)

    print("Done.")


if __name__ == "__main__":
    main()
