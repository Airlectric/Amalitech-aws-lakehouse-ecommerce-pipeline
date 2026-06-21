"""Router Lambda — entry point between EventBridge S3 Object Created events and the
Step Functions Lakehouse pipeline.

Responsibilities
----------------
1. Extract bucket/key from the EventBridge detail payload.
2. Determine the logical dataset (products, orders, order_items) from the S3 key
   prefix.  Objects outside the recognised raw/ prefixes are silently skipped so
   that ancillary writes (manifests, temp files, etc.) never trigger a pipeline run.
3. Start a Step Functions execution with a compact input envelope, injecting a
   uuid4 execution_id and UTC run_date for downstream Glue arguments and logs.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

# Map each recognised raw/ prefix to its logical dataset name.
# Order matters for prefix matching: longer prefixes should come first if any
# could be a prefix of another (they aren't here, but it's good practice).
_PREFIX_TO_DATASET = {
    "raw/products": "products",
    "raw/orders": "orders",
    "raw/order_items": "order_items",
}


def _resolve_dataset(key: str):
    """Return the logical dataset name for *key*, or None if it is not recognised.

    Matching is prefix-based so that nested paths like
    ``raw/products/2024-06-25/products.csv`` are handled correctly.
    """
    for prefix, dataset in _PREFIX_TO_DATASET.items():
        if key.startswith(prefix + "/") or key.startswith(prefix):
            return dataset
    return None


def lambda_handler(event, context):
    """Handle one EventBridge S3 Object Created event.

    Parameters
    ----------
    event   : EventBridge event dict with a ``detail`` sub-key.
    context : Lambda context (unused, present for compatibility).

    Returns
    -------
    dict with ``status`` key:
        ``{"status": "started", "execution_arn": "..."}`` on success.
        ``{"status": "skipped"}`` when the key does not match a raw/ prefix.
    """
    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    key = detail.get("object", {}).get("key", "")

    logger.info("Received event: bucket=%s key=%s", bucket, key)

    dataset = _resolve_dataset(key)
    if dataset is None:
        logger.info("Skipping key not matching any raw prefix: %s", key)
        return {"status": "skipped"}

    execution_input = {
        "bucket": bucket,
        "key": key,
        "dataset": dataset,
        "execution_id": str(uuid.uuid4()),
        "run_date": datetime.now(timezone.utc).date().isoformat(),
    }

    sfn = boto3.client("stepfunctions")
    response = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=json.dumps(execution_input),
    )

    logger.info("Started execution: arn=%s", response["executionArn"])
    return {"status": "started", "execution_arn": response["executionArn"]}
