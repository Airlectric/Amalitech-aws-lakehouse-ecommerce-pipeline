"""Archiver Lambda — called by Step Functions on pipeline success.

Copies the source object from the raw landing bucket to the archive bucket,
preserving the full key path, then deletes the source.  If any copy or delete
operation fails the function raises ``RuntimeError`` so that the Step Functions
Catch block fires and the pipeline is marked as failed rather than silently
swallowing the error.
"""

import logging
import os

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

ARCHIVED_BUCKET = os.environ["ARCHIVED_BUCKET"]

# Prefix prepended to every archived key so archived objects are easy to
# distinguish from live raw objects if the archive bucket is shared.
ARCHIVED_PREFIX = "archived"


def lambda_handler(event, context):
    """Archive a single S3 object.

    Expected event shape (as supplied by the Step Functions state machine)
    -----------------------------------------------------------------------
    {
        "bucket":       "<source-bucket>",
        "key":          "<raw/dataset/file.csv>",
        "execution_id": "<uuid>"
    }

    Returns
    -------
    dict
        ``{"archived_count": 1, "results": [{"key": ..., "archive_key": ...,
        "status": "archived"}]}`` on full success.

    Raises
    ------
    RuntimeError
        When any copy or delete operation fails, so that Step Functions can
        route to a Catch / failure state.
    """
    source_bucket = event["bucket"]
    key = event["key"]
    execution_id = event.get("execution_id", "")

    archive_key = f"{ARCHIVED_PREFIX}/{key}"

    logger.info(
        "Archiving execution_id=%s source=%s/%s destination=%s/%s",
        execution_id,
        source_bucket,
        key,
        ARCHIVED_BUCKET,
        archive_key,
    )

    s3 = boto3.client("s3")
    failed = []
    results = []

    # --- copy ---
    try:
        s3.copy_object(
            CopySource={"Bucket": source_bucket, "Key": key},
            Bucket=ARCHIVED_BUCKET,
            Key=archive_key,
        )
    except Exception as exc:
        logger.error("Copy failed for %s: %s", key, exc)
        failed.append(key)
        results.append({"key": key, "archive_key": archive_key, "status": "failed", "error": str(exc)})
        # Do NOT attempt to delete the source when the copy did not succeed.
        raise RuntimeError(f"Archive failed for {len(failed)} objects: {', '.join(failed)}") from exc

    # --- delete source only after a confirmed successful copy ---
    try:
        s3.delete_object(Bucket=source_bucket, Key=key)
    except Exception as exc:
        logger.error("Delete failed for %s: %s", key, exc)
        failed.append(key)
        results.append({"key": key, "archive_key": archive_key, "status": "failed", "error": str(exc)})
        raise RuntimeError(f"Archive failed for {len(failed)} objects: {', '.join(failed)}") from exc

    results.append({"key": key, "archive_key": archive_key, "status": "archived"})
    archived_count = sum(1 for r in results if r["status"] == "archived")

    logger.info("Archived %d object(s)", archived_count)
    return {"archived_count": archived_count, "results": results}
