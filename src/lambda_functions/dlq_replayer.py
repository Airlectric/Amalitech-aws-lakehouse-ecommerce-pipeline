"""DLQ Replayer Lambda — automatically re-drives failed pipeline events from the
dead-letter queue back into Step Functions.

Each SQS message body is an EventBridge S3 Object Created payload that the
Router Lambda failed to process. This function replicates the Router Lambda's
StartExecution logic so transient failures recover without manual intervention.

Partial batch failure reporting is enabled: individual bad messages are left in
the DLQ for inspection rather than blocking healthy messages in the same batch.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

sfn = boto3.client("stepfunctions")

_PREFIX_TO_DATASET = {
    "raw/products": "products",
    "raw/orders": "orders",
    "raw/order_items": "order_items",
}


def _resolve_dataset(key):
    for prefix, dataset in _PREFIX_TO_DATASET.items():
        if key.startswith(prefix + "/") or key.startswith(prefix):
            return dataset
    return None


def _replay_message(record):
    message_id = record.get("messageId", "unknown")
    body = record.get("body", "")

    try:
        event = json.loads(body)
    except json.JSONDecodeError:
        logger.error("Message %s has invalid JSON body; leaving in DLQ", message_id)
        return False

    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    key = detail.get("object", {}).get("key", "")

    if not bucket or not key:
        logger.error("Message %s missing bucket or key; leaving in DLQ", message_id)
        return False

    dataset = _resolve_dataset(key)
    if dataset is None:
        logger.info("Message %s key=%s not in a recognised raw/ prefix; skipping", message_id, key)
        return True

    execution_input = {
        "bucket": bucket,
        "key": key,
        "dataset": dataset,
        "execution_id": str(uuid.uuid4()),
        "run_date": datetime.now(timezone.utc).date().isoformat(),
    }

    try:
        resp = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps(execution_input),
        )
        logger.info("Replayed message %s → execution %s", message_id, resp["executionArn"])
        return True
    except ClientError as exc:
        logger.error("Failed to start execution for message %s: %s", message_id, exc)
        return False


def lambda_handler(event, context):
    failures = []
    for record in event.get("Records", []):
        if not _replay_message(record):
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
