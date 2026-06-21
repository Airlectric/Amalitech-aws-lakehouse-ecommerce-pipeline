# Lakehouse Pipeline — Runbooks

Operational procedures for the Delta Lake e-commerce lakehouse pipeline.

---

## Table of Contents

1. [Glue Job Failure Triage](#1-glue-job-failure-triage)
2. [DLQ Replay](#2-dlq-replay)
3. [Manual Backfill](#3-manual-backfill)
4. [Schema Evolution](#4-schema-evolution)
5. [Disaster Recovery](#5-disaster-recovery)

---

## 1. Glue Job Failure Triage

### 1.1 Alert path

When a Glue job fails, Step Functions catches the error and publishes to the
`{env}-lakehouse-alerts` SNS topic. The same failure increments the Step Functions
`ExecutionsFailed` metric. A second alarm fires if no successful execution occurs within
`sla_breach_hours` (default 25 h).

### 1.2 Find the root cause

```bash
# List recent failed Step Functions executions
aws stepfunctions list-executions \
    --state-machine-arn <STATE_MACHINE_ARN> \
    --status-filter FAILED \
    --query "executions[*].{arn:executionArn,start:startDate,stop:stopDate}" \
    --output table

# Inspect the failure cause from the execution history
aws stepfunctions get-execution-history \
    --execution-arn <EXECUTION_ARN> \
    --query "events[?type=='TaskFailed']"
```

**CloudWatch log groups** (one per job):

| Job | Log group |
|-----|-----------|
| products_etl | `/aws-glue/jobs/output` (filter: `job-name=dev-products-etl`) |
| orders_etl | `/aws-glue/jobs/output` (filter: `job-name=dev-orders-etl`) |
| order_items_etl | `/aws-glue/jobs/output` (filter: `job-name=dev-order-items-etl`) |
| maintenance_etl | `/aws-glue/jobs/output` (filter: `job-name=dev-maintenance-etl`) |

```bash
# Tail the most recent run log for a specific job
aws logs tail /aws-glue/jobs/output \
    --filter-pattern "dev-products-etl" \
    --since 2h
```

### 1.3 Common failure patterns

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ValueError: Schema drift detected` | Upstream added/removed CSV columns | See §4 Schema Evolution |
| `ValueError: Post-MERGE reconciliation failed` | Row count mismatch after merge | Check source CSV for truncation; re-upload and re-run |
| `Analysis exception: Table does not exist` | Delta table not yet initialised | First run after `terraform apply`; safe to re-run; or check `dwh_path` arg |
| `AnalysisException: delta.`…` is not a Delta table` | Wrong `dwh_path` variable or S3 path misconfiguration | Verify Terraform output `dwh_bucket_id` and Glue job `dwh_path` arg |
| DQ rejection rate alarm | High proportion of invalid rows | Check `rejected/` prefix for that dataset/date; review source data quality |

### 1.4 Safe re-run

All three ETL jobs are **idempotent** — re-running the same source file produces a MERGE
(update-or-insert) with no duplicate rows.

```bash
# Re-trigger via Step Functions with the same S3 event input
aws stepfunctions start-execution \
    --state-machine-arn <STATE_MACHINE_ARN> \
    --input '{
        "bucket": "<RAW_BUCKET>",
        "key":    "raw/products/products.csv",
        "dataset": "products",
        "execution_id": "<NEW_UUID>",
        "run_date": "YYYY-MM-DD"
    }'
```

Replace `dataset`, `key`, and `run_date` as appropriate. The `execution_id` should be a new
UUID4 for traceability.

---

## 2. DLQ Replay

The `{env}-pipeline-dlq` SQS queue captures two failure modes:

- **EventBridge delivery failure** — EventBridge could not invoke the Router Lambda (e.g.,
  Lambda concurrency limit, transient error). Message body is the original EventBridge S3
  event JSON.
- **Lambda async exhausted retries** — Router Lambda itself failed on all async retry
  attempts. Message body is the original invocation payload.

### 2.1 Check DLQ depth

```bash
aws sqs get-queue-attributes \
    --queue-url <DLQ_URL> \
    --attribute-names ApproximateNumberOfMessages
```

### 2.2 Replay messages

Use `scripts/replay_dlq.py`:

```bash
# Resolve the DLQ URL and router ARN from Terraform outputs
DLQ_URL=$(terraform -chdir=terraform/envs/dev output -raw pipeline_dlq_url)
ROUTER_ARN=$(aws lambda get-function-configuration \
    --function-name dev-pipeline-router \
    --query FunctionArn --output text)

# Dry run first to see what would happen
python scripts/replay_dlq.py \
    --dlq-url "$DLQ_URL" \
    --router-arn "$ROUTER_ARN" \
    --max-messages 20 \
    --dry-run

# Replay for real
python scripts/replay_dlq.py \
    --dlq-url "$DLQ_URL" \
    --router-arn "$ROUTER_ARN" \
    --max-messages 20
```

On success each message is deleted from the DLQ. On Lambda invocation failure the message
remains in the DLQ for further inspection — the script exits with code 1.

### 2.3 Manual inspect without replay

```bash
# Peek at a message without consuming it (VisibilityTimeout=0 returns it immediately)
aws sqs receive-message \
    --queue-url <DLQ_URL> \
    --max-number-of-messages 1 \
    --visibility-timeout 0 \
    --query "Messages[0].Body"
```

---

## 3. Manual Backfill

Use this when you need to re-process a range of dates — for example, after a schema fix or
after discovering that a batch of CSV files was corrupted.

### 3.1 Upload the corrected CSV files

```bash
# Upload a single dataset
python scripts/upload_raw.py \
    --bucket <RAW_BUCKET> \
    --dataset orders \
    --data-dir Data/backfill/2025-04-01 \
    --variant clean

# Upload all datasets from a backfill directory
python scripts/upload_raw.py \
    --bucket <RAW_BUCKET> \
    --data-dir Data/backfill/2025-04-01
```

EventBridge S3 `Object Created` events fire automatically for each upload and trigger the
pipeline. If EventBridge delivery fails, use the DLQ replay procedure above.

### 3.2 Trigger manually for a date range

If the CSV files are already in S3 but the executions never ran (e.g., EventBridge was
disabled), start executions directly:

```bash
STATE_MACHINE_ARN=$(terraform -chdir=terraform/envs/dev output -raw state_machine_arn)
RAW_BUCKET=$(terraform -chdir=terraform/envs/dev output -raw raw_bucket_id)

for DATE in 2025-04-01 2025-04-02 2025-04-03; do
    for DATASET in products orders order_items; do
        aws stepfunctions start-execution \
            --state-machine-arn "$STATE_MACHINE_ARN" \
            --name "backfill-${DATASET}-${DATE}-$(date +%s)" \
            --input "{
                \"bucket\":   \"$RAW_BUCKET\",
                \"key\":      \"raw/${DATASET}/${DATASET}_${DATE}.csv\",
                \"dataset\":  \"$DATASET\",
                \"execution_id\": \"$(uuidgen)\",
                \"run_date\": \"$DATE\"
            }"
        sleep 1
    done
done
```

### 3.3 Verify the backfill

```bash
# Check row count via Athena (replace database/table names as needed)
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM dev_lakehouse_dwh.orders WHERE date BETWEEN '2025-04-01' AND '2025-04-03'" \
    --work-group dev-lakehouse-workgroup \
    --query-execution-context Database=dev_lakehouse_dwh \
    --result-configuration OutputLocation=s3://<RESULTS_BUCKET>/athena-results/

# Use Delta time-travel to compare before/after (run from a Glue notebook or EMR)
# from delta.tables import DeltaTable
# dt = DeltaTable.forPath(spark, "s3://<DWH_BUCKET>/dwh/orders/")
# dt.history(10).show(truncate=False)
```

---

## 4. Schema Evolution

Follow this procedure when the upstream data team adds, renames, or removes a column from
a source CSV.

**Never skip step verification** — an undetected schema mismatch will cause the pipeline's
schema-drift guard (`check_schema_drift`) to raise a `ValueError`, halting the job.

### 4.1 Steps

1. **Identify the change.** Compare the new CSV header with the current schema in
   `src/glue_jobs/common/schemas.py`.

2. **Update `schemas.py`.** Add, rename, or remove the relevant `StructField` in the
   appropriate `get_<dataset>_schema()` function. Match the production column name and type
   exactly.

3. **Update `terraform/modules/glue-catalog/main.tf`.** Mirror the column change in the
   `aws_glue_catalog_table.<dataset>` `storage_descriptor` block so Athena consumers see
   the updated schema.

4. **Update ETL logic if needed.** If the column participates in validation rules
   (`src/glue_jobs/common/validation.py`), dedup keys, or the merge predicate
   (`src/glue_jobs/common/delta_io.py`), update those as well.

5. **Update tests.** Add or modify test fixtures in `tests/test_etl_integration.py` to
   cover the new schema. The schema-drift tests use inline CSV strings — update those too.

6. **Run tests locally** (requires Java 11 + pyspark + delta-spark):
   ```bash
   pytest tests/ -v -m spark
   ```

7. **Apply the catalog change:**
   ```bash
   terraform -chdir=terraform/envs/dev plan  -target=module.glue_catalog
   terraform -chdir=terraform/envs/dev apply -target=module.glue_catalog
   ```

8. **Run a test upload** with the new CSV to verify the pipeline end-to-end:
   ```bash
   python scripts/upload_raw.py --bucket <RAW_BUCKET> --dataset <DATASET> --dry-run
   python scripts/upload_raw.py --bucket <RAW_BUCKET> --dataset <DATASET>
   ```

9. **Backfill historical data** if the new column is required for existing rows (see §3).
   Use Delta time-travel (`RESTORE TABLE ... TO VERSION AS OF <n>`) if you need to roll
   back while the fix is prepared.

### 4.2 Adding a column — Delta compatibility note

Delta Lake allows adding nullable columns to an existing table without rewriting history.
Existing rows will read `null` for the new column. If a non-null default is required,
backfill via MERGE or a one-off Spark job.

### 4.3 Removing a column — caution

Removing a column from the Glue Catalog does not delete it from Delta. Old Parquet files
still contain the column. If you need a physical drop, run:
```sql
ALTER TABLE delta.`s3://<DWH_BUCKET>/dwh/<dataset>/` DROP COLUMN <column_name>
```
This rewrites the table (expensive for large tables) and requires Delta protocol version 2+.

---

## 5. Disaster Recovery

### 5.1 Recovery points

| Layer | Mechanism | RPO |
|-------|-----------|-----|
| Raw CSV | S3 bucket versioning (enabled) | Point-in-time |
| Delta tables | Delta transaction log + S3 versioning | Per-run (each MERGE is a version) |
| Glue job scripts | S3 versioning on the `glue-scripts` bucket | Per-deploy |
| Infrastructure | Terraform state in S3 + DynamoDB lock | Per-apply |

**RTO target:** ~30 min for a single-table restore; ~2 h for a full-environment rebuild from
Terraform (excluding data reprocessing time).

### 5.2 Delta time-travel recovery

```bash
# List Delta versions for a table (run in a Glue notebook or EMR)
from delta.tables import DeltaTable
dt = DeltaTable.forPath(spark, "s3://<DWH_BUCKET>/dwh/orders/")
dt.history(20).select("version", "timestamp", "operation", "operationMetrics").show(truncate=False)

# Read the table as of a specific version or timestamp
df_before = spark.read.format("delta") \
    .option("versionAsOf", 5) \
    .load("s3://<DWH_BUCKET>/dwh/orders/")

# Restore the table to a previous version (overwrites current)
dt.restoreToVersion(5)
# or
dt.restoreToTimestamp("2025-04-01T00:00:00Z")
```

VACUUM retains versions for `vacuum_retain_hours` (default 168 h / 7 days). Versions older
than the retain window cannot be restored via time-travel — only via S3 object versioning.

### 5.3 S3 object version restore

```bash
# List all versions of a raw file
aws s3api list-object-versions \
    --bucket <RAW_BUCKET> \
    --prefix raw/orders/orders_apr_2025.csv

# Restore a specific version by copying it back over the current key
aws s3api copy-object \
    --bucket <RAW_BUCKET> \
    --copy-source "<RAW_BUCKET>/raw/orders/orders_apr_2025.csv?versionId=<VERSION_ID>" \
    --key raw/orders/orders_apr_2025.csv
```

### 5.4 Full environment rebuild

```bash
# From a clean account with credentials and backend configured:
terraform -chdir=terraform/envs/dev init
terraform -chdir=terraform/envs/dev apply

# Then backfill all historical data:
python scripts/upload_raw.py --bucket <RAW_BUCKET>
# Monitor SFN executions until all dates are processed.
```

### 5.5 DR stance summary

- **Raw data is immutable** — source CSVs are never deleted or overwritten in place; the
  archiver Lambda moves processed files to `archived/` under a date prefix.
- **Delta history is the audit trail** — every MERGE writes a committed Delta version; the
  `ingested_at` and `source_execution_id` columns link each row back to its SFN execution.
- **No cross-region replication** is configured — acceptable for a dev/training environment;
  a production deployment should enable S3 Cross-Region Replication on both the raw and DWH
  buckets for geographic redundancy.
