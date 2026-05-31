"""Tests for the archiver Lambda handler.

The ARCHIVED_BUCKET env-var must be set before the module is imported because
``archiver.py`` reads it at module level via ``os.environ["ARCHIVED_BUCKET"]``.
"""

import os
from unittest.mock import MagicMock, patch

import pytest

# Set the required environment variable before importing the handler.
os.environ["ARCHIVED_BUCKET"] = "test-archive-bucket"

from archiver import lambda_handler  # noqa: E402 — must come after env setup


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_event(
    bucket="test-raw-bucket",
    key="raw/products/products.csv",
    execution_id="exec-lakehouse-001",
):
    return {"bucket": bucket, "key": key, "execution_id": execution_id}


def _mock_s3_client(mock_boto3):
    """Return a preconfigured mock S3 client attached to mock_boto3."""
    mock_client = MagicMock()
    mock_boto3.client.return_value = mock_client
    return mock_client


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@patch("archiver.boto3")
def test_archive_success(mock_boto3, lambda_context):
    """Happy path: copy_object and delete_object both succeed; archived_count=1."""
    mock_s3 = _mock_s3_client(mock_boto3)
    event = _make_event()

    result = lambda_handler(event, lambda_context)

    assert result["archived_count"] == 1
    assert len(result["results"]) == 1
    assert result["results"][0]["status"] == "archived"

    mock_boto3.client.assert_called_once_with("s3")
    mock_s3.copy_object.assert_called_once()
    mock_s3.delete_object.assert_called_once()


@patch("archiver.boto3")
def test_archive_fails_loud(mock_boto3, lambda_context):
    """When copy_object raises, the handler must raise RuntimeError (fail-loud).

    Critically, delete_object must NOT be called — we should never delete the
    source if the copy did not succeed.
    """
    mock_s3 = _mock_s3_client(mock_boto3)
    mock_s3.copy_object.side_effect = Exception("S3 copy error: permission denied")

    event = _make_event()

    with pytest.raises(RuntimeError):
        lambda_handler(event, lambda_context)

    mock_s3.delete_object.assert_not_called()


@patch("archiver.boto3")
def test_archive_preserves_key_structure(mock_boto3, lambda_context):
    """The archived key must embed the original source key path under the archive prefix.

    Given source key ``raw/orders/2024-06-25/orders.csv`` the copy destination key
    must be ``archived/raw/orders/2024-06-25/orders.csv``.
    """
    mock_s3 = _mock_s3_client(mock_boto3)
    source_key = "raw/orders/2024-06-25/orders.csv"
    event = _make_event(key=source_key)

    result = lambda_handler(event, lambda_context)

    copy_call = mock_s3.copy_object.call_args[1]
    assert copy_call["CopySource"] == {"Bucket": "test-raw-bucket", "Key": source_key}
    assert copy_call["Bucket"] == "test-archive-bucket"
    # The archive key must start with the archive prefix and retain the full source path.
    archive_key = copy_call["Key"]
    assert archive_key.startswith("archived/")
    assert source_key in archive_key

    # The result record must also carry the correct archive_key.
    assert result["results"][0]["archive_key"] == archive_key


@patch("archiver.boto3")
def test_archive_delete_failure_raises(mock_boto3, lambda_context):
    """When delete_object raises after a successful copy, RuntimeError is still raised."""
    mock_s3 = _mock_s3_client(mock_boto3)
    mock_s3.delete_object.side_effect = Exception("S3 delete error: permission denied")

    event = _make_event()

    with pytest.raises(RuntimeError):
        lambda_handler(event, lambda_context)

    # copy was attempted and succeeded; only delete failed
    mock_s3.copy_object.assert_called_once()
    mock_s3.delete_object.assert_called_once()
