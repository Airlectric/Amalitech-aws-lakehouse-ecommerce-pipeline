import os
import sys
import pytest
from unittest.mock import MagicMock

# Make the Lambda handlers and Glue scripts importable without installing them
# as packages.  Both directories are inserted at position 0 so they take
# precedence over any installed versions.
HANDLERS_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "src", "lambda_functions")
)
GLUE_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "src", "glue_jobs")
)

sys.path.insert(0, GLUE_DIR)
sys.path.insert(0, HANDLERS_DIR)


def pytest_configure(config):
    """Register custom markers so -m filtering works cleanly."""
    config.addinivalue_line(
        "markers",
        "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    )


@pytest.fixture
def lambda_context():
    """Minimal mock of the AWS Lambda context object."""
    ctx = MagicMock()
    ctx.aws_request_id = "test-request-id-lakehouse"
    ctx.function_name = "test-lakehouse-function"
    ctx.invoked_function_arn = (
        "arn:aws:lambda:us-east-1:123456789012:function:test-lakehouse-function"
    )
    return ctx
