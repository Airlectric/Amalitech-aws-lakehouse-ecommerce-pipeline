"""Tests for the router Lambda handler.

The STATE_MACHINE_ARN env-var must be set before the module is imported because
``router.py`` reads it at module level via ``os.environ["STATE_MACHINE_ARN"]``.
"""

import json
from datetime import date
import os
from unittest.mock import MagicMock, patch

# Set the required environment variable before importing the handler so the
# module-level os.environ lookup does not raise a KeyError.
os.environ["STATE_MACHINE_ARN"] = (
    "arn:aws:states:us-east-1:123456789012:stateMachine:lakehouse-pipeline"
)

from router import lambda_handler  # noqa: E402 — must come after env setup


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_event(bucket="test-raw-bucket", key="raw/products/products.csv"):
    """Return a minimal EventBridge S3 Object Created event dict."""
    return {
        "detail": {
            "bucket": {"name": bucket},
            "object": {"key": key},
        }
    }


def _mock_sfn_client(mock_boto3, execution_arn="arn:aws:states:us-east-1:123:execution:x:y"):
    """Wire up the mock boto3 client so start_execution returns a plausible ARN."""
    mock_client = MagicMock()
    mock_boto3.client.return_value = mock_client
    mock_client.start_execution.return_value = {"executionArn": execution_arn}
    return mock_client


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@patch("router.boto3")
def test_router_valid_products_key(mock_boto3, lambda_context):
    """A key under raw/products/ resolves to dataset='products' and starts an execution."""
    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="raw/products/products.csv")

    result = lambda_handler(event, lambda_context)

    assert result["status"] == "started"
    assert "execution_arn" in result

    mock_boto3.client.assert_called_once_with("stepfunctions")
    mock_sfn.start_execution.assert_called_once()

    call_kwargs = mock_sfn.start_execution.call_args[1]
    payload = json.loads(call_kwargs["input"])
    assert payload["dataset"] == "products"
    assert payload["bucket"] == "test-raw-bucket"
    assert payload["key"] == "raw/products/products.csv"
    assert "execution_id" in payload
    date.fromisoformat(payload["run_date"])


@patch("router.boto3")
def test_router_valid_orders_key(mock_boto3, lambda_context):
    """A key under raw/orders/ resolves to dataset='orders'."""
    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="raw/orders/orders.csv")

    result = lambda_handler(event, lambda_context)

    assert result["status"] == "started"
    mock_sfn.start_execution.assert_called_once()

    payload = json.loads(mock_sfn.start_execution.call_args[1]["input"])
    assert payload["dataset"] == "orders"


@patch("router.boto3")
def test_router_valid_order_items_key(mock_boto3, lambda_context):
    """A key under raw/order_items/ resolves to dataset='order_items'."""
    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="raw/order_items/order_items.csv")

    result = lambda_handler(event, lambda_context)

    assert result["status"] == "started"
    mock_sfn.start_execution.assert_called_once()

    payload = json.loads(mock_sfn.start_execution.call_args[1]["input"])
    assert payload["dataset"] == "order_items"


@patch("router.boto3")
def test_router_skips_non_raw_key(mock_boto3, lambda_context):
    """A key that does not start with a raw/ prefix must be skipped.

    StartExecution must NOT be called — we should not waste a Step Functions
    execution on objects that are not part of the raw ingestion flow.
    """
    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="archived/products/products.csv")

    result = lambda_handler(event, lambda_context)

    assert result["status"] == "skipped"
    mock_sfn.start_execution.assert_not_called()


@patch("router.boto3")
def test_router_skips_unrecognised_prefix(mock_boto3, lambda_context):
    """Keys in unrecognised top-level prefixes are silently skipped."""
    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="manifests/products/products.csv")

    result = lambda_handler(event, lambda_context)

    assert result["status"] == "skipped"
    mock_sfn.start_execution.assert_not_called()


@patch("router.boto3")
def test_router_execution_id_is_uuid(mock_boto3, lambda_context):
    """Each invocation injects a fresh uuid4 execution_id into the SFN input."""
    import uuid

    mock_sfn = _mock_sfn_client(mock_boto3)
    event = _make_event(key="raw/orders/2024-01-01/orders.csv")
    lambda_handler(event, lambda_context)

    payload = json.loads(mock_sfn.start_execution.call_args[1]["input"])
    # Must be parseable as a UUID (raises ValueError if not).
    uuid.UUID(payload["execution_id"])
