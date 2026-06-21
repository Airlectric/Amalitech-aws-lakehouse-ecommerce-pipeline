"""
Re-drive messages from the pipeline dead-letter queue (DLQ) back to the
Router Lambda so they are re-processed by Step Functions.

The DLQ receives two kinds of messages:
  • EventBridge failed-delivery events — when EventBridge could not invoke
    the Router Lambda (body is the raw EventBridge event JSON).
  • Lambda async-invocation failure records — when the Lambda itself failed
    after exhausted retries (body is the original Lambda invocation payload).

This script reads up to --max-messages messages from the DLQ, invokes the
Router Lambda with each message body, and deletes the message on success.
On invocation failure the message is left in the DLQ for further inspection.

Usage
-----
    python replay_dlq.py \\
        --dlq-url  https://sqs.us-east-1.amazonaws.com/123456789/dev-pipeline-dlq \\
        --router-arn arn:aws:lambda:us-east-1:123456789:function:dev-pipeline-router \\
        [--max-messages 10] [--dry-run] [--region us-east-1]

    # Resolve values from Terraform outputs automatically:
    DLQ_URL=$(terraform -chdir=terraform/envs/dev output -raw pipeline_dlq_url)
    ROUTER_ARN=$(terraform -chdir=terraform/envs/dev output -raw router_lambda_arn 2>/dev/null || \\
                 aws lambda get-function-configuration \\
                     --function-name dev-pipeline-router \\
                     --query FunctionArn --output text)
    python scripts/replay_dlq.py --dlq-url "$DLQ_URL" --router-arn "$ROUTER_ARN"
"""

import argparse
import json
import os
import sys

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def parse_args():
    p = argparse.ArgumentParser(description="Re-drive pipeline DLQ messages.")
    p.add_argument("--dlq-url", required=True, help="SQS DLQ queue URL")
    p.add_argument("--router-arn", required=True, help="Router Lambda function ARN")
    p.add_argument(
        "--max-messages",
        type=int,
        default=10,
        help="Maximum number of messages to replay (default: 10)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would happen without invoking Lambda or deleting messages",
    )
    p.add_argument(
        "--region",
        default=os.environ.get("AWS_DEFAULT_REGION") or os.environ.get("AWS_REGION", "us-east-1"),
        help="AWS region (default: AWS_DEFAULT_REGION / AWS_REGION / us-east-1)",
    )
    return p.parse_args()


def receive_messages(sqs, queue_url, max_count):
    """Yield SQS messages from the queue up to max_count total."""
    remaining = max_count
    while remaining > 0:
        batch = min(remaining, 10)
        resp = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=batch,
            WaitTimeSeconds=5,
            AttributeNames=["All"],
        )
        msgs = resp.get("Messages", [])
        if not msgs:
            break
        for msg in msgs:
            yield msg
        remaining -= len(msgs)


def invoke_router(lam, router_arn, payload_str, dry_run):
    """Invoke the Router Lambda with payload_str. Returns True on success."""
    if dry_run:
        print(f"  [DRY-RUN] would invoke {router_arn} with payload: {payload_str[:200]}")
        return True

    try:
        resp = lam.invoke(
            FunctionName=router_arn,
            InvocationType="RequestResponse",
            Payload=payload_str.encode(),
        )
    except (BotoCoreError, ClientError) as exc:
        print(f"  ERROR: Lambda invoke failed: {exc}", file=sys.stderr)
        return False

    status = resp.get("StatusCode", 0)
    func_error = resp.get("FunctionError")
    if func_error or status >= 300:
        body = resp["Payload"].read().decode()
        print(f"  ERROR: Lambda returned FunctionError={func_error} status={status}: {body}", file=sys.stderr)
        return False

    body = resp["Payload"].read().decode()
    print(f"  OK: status={status} response={body[:120]}")
    return True


def delete_message(sqs, queue_url, receipt_handle, dry_run):
    if dry_run:
        print("  [DRY-RUN] would delete message from DLQ")
        return
    sqs.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)


def main():
    args = parse_args()
    sqs = boto3.client("sqs", region_name=args.region)
    lam = boto3.client("lambda", region_name=args.region)

    print(f"Replaying up to {args.max_messages} messages from DLQ.")
    print(f"  DLQ    : {args.dlq_url}")
    print(f"  Router : {args.router_arn}")
    if args.dry_run:
        print("  Mode   : DRY-RUN (no mutations)")
    print()

    replayed = 0
    failed = 0

    for msg in receive_messages(sqs, args.dlq_url, args.max_messages):
        msg_id = msg["MessageId"]
        body = msg["Body"]
        receipt = msg["ReceiptHandle"]

        print(f"Message {msg_id}:")

        # Both EventBridge delivery failures and Lambda async failures store
        # the original event as the message body. Pass it straight to Lambda.
        try:
            json.loads(body)  # validate it is JSON
        except json.JSONDecodeError:
            print(f"  WARN: message body is not valid JSON; skipping.\n  body={body[:200]}", file=sys.stderr)
            failed += 1
            continue

        success = invoke_router(lam, args.router_arn, body, args.dry_run)
        if success:
            delete_message(sqs, args.dlq_url, receipt, args.dry_run)
            replayed += 1
        else:
            failed += 1

    print(f"\nDone. replayed={replayed} failed={failed}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
