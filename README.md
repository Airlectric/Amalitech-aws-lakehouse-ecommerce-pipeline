# Lakehouse Architecture for E-Commerce Transactions

A production-grade **Lakehouse** on AWS that ingests raw e-commerce transactional data from S3,
cleans and deduplicates it using **Delta Lake** on **AWS Glue + PySpark**, and exposes it for
downstream analytics through **Amazon Athena**. Orchestrated end-to-end by **AWS Step Functions**
with CI/CD on **GitHub Actions**.

---

## Architecture

![Lakehouse Architecture](docs/lakehouse-architecture.png)

> The current dev architecture is fully serverless and does **not** attach Lambda or Glue jobs to a VPC. EventBridge, Lambda, Step Functions, Glue, S3, Athena, CloudWatch, CloudTrail, SNS, SQS, IAM, and KMS communicate through AWS-managed service endpoints with least-privilege IAM and KMS encryption. Numbered badges 1–7 track the pipeline flow described below.

### Diagram Walkthrough

The numbered badges in the diagram correspond to the main pipeline flow:

1. **Raw landing:** The producer uploads CSV files (products, orders, order_items) into the Raw S3
   bucket. An S3 `Object Created` event is emitted automatically.
2. **Event routing:** EventBridge captures the event and invokes the **Router Lambda**. Delivery
   failures after retries land in the **SQS dead-letter queue** — no event is silently lost.
3. **Orchestration trigger:** The Router calls Step Functions `StartExecution` and hands off the
   payload (bucket, key, dataset, run date). Step Functions routes the event by dataset and
   orchestrates the remaining states.
4. **Delta ETL:** Step Functions starts the matching managed **Glue PySpark + Delta Lake** job
   (`products-etl`, `orders-etl`, or `order-items-etl`; full-load events can run all three in
   parallel). Each job reads raw CSV with explicit schemas, validates rows, deduplicates by primary
   key, and writes invalid rows with rejection reasons to **Rejected S3**.
5. **Delta lakehouse storage:** Valid rows are merged into **lakehouse-dwh S3** as Delta tables via
   `MERGE INTO`, giving idempotent upserts and ACID transaction logs for `products`, `orders`, and
   `order_items`.
6. **Archival:** On successful ETL, the **Archive Lambda** moves processed source files from
   `raw/` to **Archived S3**. It fails loud on any copy/delete error so Step Functions `Catch` can
   alert instead of reporting a false success.
7. **Catalog and analytics:** Delta tables are registered in the **Glue Data Catalog**. **Athena
   engine v3** reads them natively through the Delta transaction log and writes encrypted query
   results to the Athena results bucket for analyst access.

Failures at any step trigger SNS alerts to on-call and EventBridge/router delivery failures are
captured in the SQS DLQ. **CloudTrail** audits data-movement events across S3, Glue, and Step
Functions.

---

## Data Flow

| Zone | Bucket | Format | Description |
|---|---|---|---|
| Raw | `<environment>-lakehouse-raw-<suffix>` | CSV | Incoming files, immutable source of truth |
| Processed | `<environment>-lakehouse-dwh-<suffix>` | Delta | ACID tables, deduped, schema-enforced |
| Rejected | `<environment>-lakehouse-rejected-<suffix>` | Parquet | Invalid rows with rejection reasons |
| Archived | `<environment>-lakehouse-archived-<suffix>` | CSV | Source files after successful ingestion |

### Delta Table Schema

| Table | PK | Partition | Notes |
|---|---|---|---|
| `products` | `product_id` | none | Small dim, broadcast-friendly |
| `orders` | `order_id` | `date` | Daily partition for time-range pruning |
| `order_items` | `id` | `date` | Daily partition |

---

## Tech Stack

| Layer | Service |
|---|---|
| Orchestration | AWS Step Functions (Standard) |
| ETL | AWS Glue 4.0 (PySpark + Delta Lake), Glue Data Catalog |
| Storage | Amazon S3 (Delta format), SSE-KMS |
| Event routing | Amazon EventBridge, Amazon SQS (dead-letter queue) |
| Compute | AWS Lambda (Python 3.12 router + archiver) |
| Analytics | Amazon Athena (engine v3, native Delta) |
| Security | KMS CMKs, IAM least privilege, S3 public access blocks, TLS-only bucket policies |
| Observability | CloudWatch (dashboard + alarms), CloudTrail (audit), SNS alerts |
| IaC | Terraform 1.7+, modular composition |
| CI/CD | GitHub Actions (pytest + terraform fmt/validate/plan, OIDC, plan-only) |

---

## Repository Layout

```
lakehouse-ecommerce-pipeline/
├── glue/
│   ├── common/
│   │   ├── schemas.py          # Explicit StructType per dataset
│   │   ├── validation.py       # Null-PK, timestamp, range rules; split valid/rejected
│   │   └── delta_io.py         # Window dedup, Delta MERGE upsert, rejected writer
│   ├── products_etl.py
│   ├── orders_etl.py
│   └── order_items_etl.py
├── lambda/handlers/
│   ├── router.py               # EventBridge → Step Functions (not VPC-attached)
│   └── archiver.py             # raw/ → archived/ on success (fail-loud)
├── tests/
│   ├── conftest.py
│   ├── requirements.txt
│   ├── test_router_lambda.py
│   ├── test_archive_lambda.py
│   ├── test_schemas.py
│   └── test_validation.py
├── scripts/
│   ├── convert_xlsx_to_csv.py  # Convert orders/order_items .xlsx → CSV
│   ├── generate_dirty_data.py  # Inject nulls/dupes/orphan FKs for testing
│   └── upload_raw.py           # Upload CSVs to S3 raw zone (simulate ingestion)
├── docs/
│   └── lakehouse-architecture.png        # Architecture diagram (drawio XML source is gitignored)
├── terraform/
│   ├── bootstrap/              # State backend (S3 + DynamoDB + KMS + GitHub OIDC)
│   ├── envs/dev/               # Root composition for dev environment
│   └── modules/
│       ├── kms/                # CMKs: s3-data-lake, glue, logs
│       ├── s3-data-lake/       # 7 buckets with lifecycle + SSE-KMS
│       ├── iam-roles/          # Least-privilege roles for all compute
│       ├── glue-jobs/          # 3 Delta-enabled managed Glue jobs
│       ├── glue-catalog/       # lakehouse-dwh DB + Delta table registrations
│       ├── lambda-functions/   # Router + Archiver + SQS DLQ
│       ├── step-functions/     # Standard state machine ASL
│       ├── eventbridge/        # S3 Object Created → Router + DLQ
│       ├── athena/             # Analytics workgroup (SSE-KMS results)
│       └── observability/      # Dashboard, alarms, CloudTrail, SNS
├── config/backend-dev.hcl.example
├── statemachine/               # Optional standalone SFN ASL
└── .github/workflows/ci.yml    # pytest → terraform fmt/validate/plan
```

---

## Setup

### Prerequisites
- AWS account with admin permissions
- Terraform 1.7+
- Python 3.12+
- GitHub repository (for CI/CD)

### Quick default-account run

The helper below uses the AWS CLI default credential chain (`AWS_PROFILE` if set, otherwise the
default account), preserves existing ignored Terraform config files, and runs the local prep,
bootstrap, dev apply, and raw upload flow:

```bash
# Clean-data e2e path
AUTO_APPROVE=true scripts/aws_e2e.sh all

# Clean + dirty uploads after apply
AUTO_APPROVE=true UPLOAD_VARIANT=both scripts/aws_e2e.sh all

# Validate and plan only
scripts/aws_e2e.sh plan
```

Project 2 bootstrap expects the account-level GitHub OIDC provider
`token.actions.githubusercontent.com` to already exist. Project 1 bootstrap creates it; if Project 2
is run standalone, create or import that provider before running `scripts/aws_e2e.sh bootstrap`.

### 1. Prepare the data

```bash
# Convert xlsx → CSV (run once)
python scripts/convert_xlsx_to_csv.py

# Optional: generate dirty data to test validation logic
python scripts/generate_dirty_data.py
```

### 2. Bootstrap state backend

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit with your values
terraform init && terraform apply
```

### 3. Set GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_TERRAFORM_ROLE_ARN` | From bootstrap output |
| `AWS_ACCOUNT_ID` | Your AWS account ID |

### 4. Deploy dev environment

```bash
cd terraform/envs/dev
cp ../../../config/backend-dev.hcl.example backend-dev.hcl
# Edit backend-dev.hcl with your state bucket details
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (bucket_suffix, alert_emails)
terraform init -backend-config=backend-dev.hcl
terraform plan
terraform apply
```

### 5. Simulate ingestion

```bash
python scripts/upload_raw.py --bucket <your-raw-bucket>
# Watch the Step Functions execution in the AWS console
```

---

## Testing

```bash
pip install -r tests/requirements.txt
python -m pytest tests/ -v --ignore=tests/test_validation.py   # fast (no Spark)
python -m pytest tests/ -v                                      # all (requires PySpark)
```

Test coverage:
- **test_router_lambda**: valid dataset keys start execution; non-raw keys skipped
- **test_archive_lambda**: success archives and deletes; copy failure raises RuntimeError (fail-loud)
- **test_schemas**: exact field names for all 3 StructType schemas (no Spark needed)
- **test_validation**: null-PK, bad-timestamp, and range-violation rejection logic

---

## Delta Time-Travel

Every MERGE into a Delta table commits a new version. Use time-travel to audit history,
troubleshoot a bad run, or roll back to a known-good state.

```python
from delta.tables import DeltaTable

# List the last 10 operations on the orders table
dt = DeltaTable.forPath(spark, "s3://<DWH_BUCKET>/dwh/orders/")
dt.history(10).select("version", "timestamp", "operation", "operationMetrics").show(truncate=False)

# Read the table as of a specific version
df_v3 = spark.read.format("delta").option("versionAsOf", 3).load("s3://<DWH_BUCKET>/dwh/orders/")

# Read the table as of a timestamp (UTC)
df_before = spark.read.format("delta") \
    .option("timestampAsOf", "2025-04-01T00:00:00Z") \
    .load("s3://<DWH_BUCKET>/dwh/orders/")

# Restore the table to a previous version (permanent, overwrites current)
dt.restoreToVersion(3)
```

> **Retention window:** the daily maintenance job runs `VACUUM RETAIN 168h` (7 days). Versions
> older than 7 days cannot be restored via time-travel; use S3 object versioning for older
> recovery (see `docs/runbooks.md §5.3`).

---

## Production Hardening

This pipeline has been hardened across five tiers of the production-readiness audit. Key
additions beyond the base implementation:

| Area | What was added |
|------|---------------|
| Correctness | Referential integrity checks; empty-file guard; schema-drift detection; post-MERGE reconciliation |
| Observability | CloudWatch DQ metrics (`Lakehouse/DQ`); SLA and rejection-rate alarms; X-Ray active tracing |
| Lineage | `ingested_at` and `source_execution_id` columns on all Delta rows |
| Maintenance | Daily OPTIMIZE + VACUUM Glue job via EventBridge Scheduler |
| Scale | Glue auto-scaling; configurable worker type/count/timeout; Athena per-query scan limit |
| Security | CloudTrail logs bucket SSE-KMS; S3 object tagging convention |
| Operations | Runbooks (triage, DLQ replay, backfill, schema evolution, DR); `scripts/replay_dlq.py` |

Full details: [`docs/production-readiness-audit.md`](docs/production-readiness-audit.md)  
Operational procedures: [`docs/runbooks.md`](docs/runbooks.md)

---

## Design Decisions

### Why Delta Lake instead of plain Parquet?
Delta gives us ACID transactions, schema enforcement, `MERGE INTO` for idempotent upserts, and
time-travel — all essential for a reliable lakehouse. Plain Parquet can't guarantee exactly-once
semantics on re-runs; Delta's transaction log can.

### Why no VPC for the dev pipeline?
The current implementation does not provision a VPC, subnets, NAT Gateway, or VPC endpoints. The
pipeline services are AWS-managed/serverless components that can access S3, Glue, Step Functions,
Athena, SNS, SQS, CloudWatch, CloudTrail, IAM, and KMS through AWS service endpoints. For this
test/dev project, removing the VPC keeps the architecture simpler, avoids NAT and PrivateLink
endpoint cost, and removes Glue networking failure modes while preserving encryption and
least-privilege IAM.

### Why is the Router Lambda not VPC-attached?
It only calls the Step Functions API. Attaching it to a VPC would add ENI cold-start behavior and
networking cost without improving the security boundary for this dev architecture.

### Why `--datalake-formats delta` instead of PyPI?
Glue 4.0 bundles the Delta JARs natively. This means the Spark jobs run without downloading
Delta packages from PyPI — unlike a `pip install` approach, which would require external package
access during job startup.

### Why job bookmarks disabled?
Delta MERGE INTO is the idempotency mechanism. Bookmarks (incremental "only new data") fight the
explicit-partition + overwrite design and add dead, misleading config.

---

## Outputs (after `terraform apply`)

| Output | Description |
|---|---|
| `raw_bucket_id` | Raw S3 bucket (CSV landing zone) |
| `dwh_bucket_id` | lakehouse-dwh S3 bucket (Delta tables) |
| `step_functions_arn` | State machine ARN |
| `sns_topic_arn` | Pipeline alert topic |
| `glue_catalog_database` | Glue DB name for Athena queries |
| `pipeline_dlq_arn` | Dead-letter queue ARN |

---

## Cleanup

```bash
cd terraform/envs/dev
terraform destroy
```

> The GitHub Actions manual `destroy` workflow runs `scripts/empty_terraform_s3_buckets.sh` before
> `terraform destroy`. The script reads Terraform state, finds Terraform-managed S3 buckets,
> suspends versioning, and deletes current objects plus object versions/delete markers so bucket
> deletion is not blocked.
