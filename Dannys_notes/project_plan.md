# Plan: Lakehouse Architecture for E-Commerce Transactions (Project 2)

*Updated 2026-05-31 — folds in the lessons learned while correcting Project 1, and adds a
brief-compliance matrix so the plan provably satisfies the instruction PDF.*

## Context

Project 2 (`Project 2 - Lakehouse Architecture/`) is a brand-new build. Today its folder holds
**only** the brief (`Building a Lakehouse Using PySpark Delta Tables & S3.pdf`) and three raw data
files — no code, no IaC, no CI.

There are **two instruction sources**, and the plan must satisfy both without conflict:
1. **The official brief PDF** (the graded instruction document) — see the **Brief-compliance matrix**
   at the end; every mission item / deliverable maps to a concrete plan element.
2. **The user's added architecture requirements** (Cloud Architect / Principal Data Engineer brief):
   secure VPC topology, scoped Security Groups, VPC Endpoints (PrivateLink), least-privilege IAM,
   KMS CMK at rest + TLS in transit, observability (CloudWatch + CloudTrail + X-Ray), and
   **cost optimization**. These are **additive** — they layer on top of the brief, never contradict it.

**Sibling Project 1** (`music-streaming-data-pipeline`) is the reference template for module
conventions, naming, tagging, IAM scoping, and CI. We reuse its *patterns* and its hard-won
*corrections* (below); we do not modify it. Project 1's `AGENT.md`/`CLAUDE.md` rule applies:
**no AI co-author trailers / "Generated with Claude" footers** in any commit, PR, or generated doc.

### Confirmed design decisions
1. **S3 topology:** multiple buckets per zone (cleaner IAM + lifecycle scoping).
2. **Trigger:** `S3 PutObject → EventBridge → router Lambda → Step Functions StartExecution` (EDA).
3. **Athena + Delta:** native Delta on **Athena engine v3** (reads the `_delta_log`; no symlink manifests).
4. **CI/CD:** plan-only — `pytest → terraform fmt/validate/plan` via GitHub OIDC; no live `apply`.
5. **Networking:** **single-AZ by default for cost** (see Lessons #4); list-typed AZ vars so multi-AZ
   is a one-line change if HA is ever needed.

### Lessons carried from Project 1 (applied here from the start)
1. **Right-size compute.** Use Spark **only** for the heavy Delta ETL. The archive step is a small
   **Lambda** (copy+delete), never a Spark job. (In P1, a Spark job was loading a few hundred rows —
   wasteful. P2 avoids that by design.)
2. **No dead bookmark config.** Delta **MERGE** is the idempotency mechanism here, so Glue jobs run
   with `--job-bookmark-disable`. (P1 had bookmarks + overwrite fighting each other.)
3. **No silent event loss.** Add an **SQS dead-letter queue** + bounded retries on the
   EventBridge→router and async-router path from day one. (P1 A4.)
4. **Interface VPC endpoints cost money (per-AZ).** Default to **single-AZ** so we don't pay ~2× for
   ~10–12 interface endpoints. Flag the endpoint cost explicitly and keep them trimmable. (P1 C3 cost
   reconsideration: multi-AZ ≈ +$87/mo for HA a course project doesn't need.)
5. **Least-privilege CI role.** The plan-only pipeline gets `ReadOnlyAccess` + scoped state-backend
   access, **not** broad write or `iam:PassRole`. A future apply pipeline uses a separate role. (P1 C5.)
6. **Fail loud.** The archive Lambda **raises** on partial failure so Step Functions `Catch` can alert,
   rather than reporting a false success. (P1 archiver fix.)
7. **Delta needs no PyPI.** Delta on Glue 4.0 is enabled via `--datalake-formats delta` (bundled), so
   the Spark jobs run fully **inside** the private subnet with no internet egress — unlike P1's
   pyarrow Python Shell job, which had to stay out of the VPC to reach PyPI.

### Key data findings (from sample inspection)
- `products.csv` — 1000 rows: `product_id, department_id, department, product_name`.
- `orders_apr_2025.xlsx` — 500 rows: `order_num, order_id, user_id, order_timestamp, total_amount, date`.
- `order_items_apr_2025.xlsx` — 2768 rows: `id, order_id, user_id, days_since_prior_order, product_id, add_to_cart_order, reordered, order_timestamp, date`.
- Samples have **no nulls and no duplicates** → ship a **dirty-data generator** (nulls / dupes /
  orphan FKs / bad timestamps) so validation + dedup are provably exercised.
- Two sources are `.xlsx`; the brief says "ingested from CSVs" → a **prep step converts xlsx → CSV**
  before landing in `raw/` (no conflict with the brief — it standardizes on CSV as the brief states).

---

## Target Architecture

```
                 (1) PutObject              (2) Object Created          (3) StartExecution
 producer ─► raw/ S3 bucket ───► EventBridge rule ───► router Lambda ───► Step Functions (Standard)
                                       │ (delivery fails)                        │
                                       ▼                                         │
                                  SQS dead-letter queue                          │
                 ┌──────────────────────────────────────────────────────────────┤
                 ▼ (4) StartJobRun.sync (Map, one per dataset)                   │
        Glue PySpark + Delta job  ──►  lakehouse-dwh/ S3 (Delta tables)          │
                 │  rejected rows ─► rejected/ S3 (+ reasons, counts)            │
                 ▼ (5) on success                                               ▼ (failure)
        Archive Lambda: raw/ ─► archived/  (fails loud)   SNS alert ◄── Catch/Retry/Timeout
                 │
                 ▼ (6) optional
        Glue Crawler / Athena validation query  ──►  Glue Data Catalog ──► Athena (engine v3)
```

The Spark/Delta Glue jobs, the router, and the archive Lambda run **inside the VPC private subnet**;
AWS API traffic stays on **VPC endpoints** (gateway for S3/DynamoDB, interface for the rest). Data
stores are reached only via those endpoints — no internet route on the data path.

---

## Repository layout (new — mirrors Project 1)

```
Project 2 - Lakehouse Architecture/
  README.md                       # architecture, design justifications, partitioning rationale, diagram
  CLAUDE.md                       # P1 convention: no AI co-author trailers
  Data/                           # existing raw samples (products.csv, *.xlsx)
  docs/                           # architecture diagram (drawio/png)
  scripts/
    convert_xlsx_to_csv.py        # orders/order_items .xlsx -> CSV
    generate_dirty_data.py        # inject nulls/dupes/orphan FKs/bad timestamps for testing
    upload_raw.py                 # push CSVs into raw/ bucket (simulate ingestion)
  glue/                           # PySpark sources (synced to glue-scripts bucket by TF)
    common/ { schemas.py, validation.py, delta_io.py }
    products_etl.py / orders_etl.py / order_items_etl.py
  statemachine/                   # optional standalone ASL JSON
  tests/                          # pytest: validation, dedup, schema, router, archive (moto/mock; openpyxl)
  config/ backend-dev.hcl.example
  .github/workflows/ci.yml        # test -> fmt/validate/plan, OIDC, scoped to main
  terraform/
    bootstrap/                    # state backend: S3 + DynamoDB lock + KMS + GitHub OIDC role (scoped)
    envs/dev/                     # root composition + *.tfvars.example
    modules/
      networking/                 # VPC, 3-tier subnets (single-AZ default), SGs, VPC endpoints, flow logs
      kms/                        # CMKs: s3-data-lake, glue, logs (rotation, aliases)
      s3-data-lake/               # raw, lakehouse-dwh, archived, rejected, glue-scripts, athena-results, access-logs
      iam-roles/                  # least-privilege: glue, router-lambda, archive-lambda, step-functions, eventbridge
      glue-jobs/                  # 3 Delta-enabled Glue jobs + NETWORK connection + script upload
      glue-catalog/               # lakehouse-dwh database (+ Delta table regs / optional crawler)
      lambda-functions/           # router + archive Lambdas (VPC-attached) + SQS DLQ + handler code
      step-functions/             # Standard state machine ASL (Map, Retry, Catch, Timeout)
      eventbridge/                # S3 Object Created rule -> router Lambda (+ retry_policy + DLQ)
      athena/                     # workgroup (SSE-KMS results, enforce config)
      observability/              # dashboard, alarms (Glue/SFN/Lambda), log groups, CloudTrail
```

Module file convention mirrors P1 (`main/variables/locals/outputs/versions.tf`; `>= 1.7`, `aws ~> 5.0`).
Tags: `{ Environment, ManagedBy="terraform", Domain=<module>, Project="lakehouse-ecommerce" }`.

---

## Layer-by-layer design

### 1. Networking & Security (module `networking`)
- **VPC** `10.0.0.0/16`. Three subnet **tiers** (per the user's requirement), **single-AZ by default**:
  - **Public** (`10.0.0.0/24`) — IGW + a single NAT Gateway for controlled egress only.
  - **Private** (`10.0.10.0/24`) — Glue + Lambda compute; route to NAT for any egress.
  - **Isolated** (`10.0.20.0/24`) — data-store reach; no internet route; S3/DynamoDB via gateway endpoints.
  - AZ/CIDR lists are variables → add a 2nd AZ later for HA with no code change.
- **Security Groups** (HTTPS-only between tiers): `endpoints` (443 from glue+lambda), `glue`, `lambda`. No `0.0.0.0/0` ingress.
- **VPC Endpoints (PrivateLink):** Gateway `s3`, `dynamodb` (free). Interface `glue, states, kms, logs,
  monitoring, sns, sts, athena` (+ `ecr.api/ecr.dkr` only if needed).
  > **Cost flag (P1 lesson #4):** interface endpoints bill ~$7/AZ/mo each. Single-AZ keeps this ~$50–60/mo.
  > If cost must be ~$0, the fallback is to drop interface endpoints and let compute use public AWS
  > endpoints over TLS (IAM + KMS still enforce security) — documented as the cheap alternative.
- **VPC Flow Logs** → CloudWatch (KMS-encrypted), 30-day retention.
- **Single NAT GW** (not per-AZ) to cap NAT cost; the data path uses endpoints, so NAT is rarely hit.

### 2. Encryption (module `kms`)
- CMKs `s3-data-lake`, `glue`, `logs` (rotation on, aliases, scoped key policies).
- **At rest:** SSE-KMS on all buckets (`bucket_key_enabled = true`), Glue temp, logs, Athena results.
- **In transit:** bucket policies `Deny` on `aws:SecureTransport=false`; all API calls over HTTPS.

### 3. Storage (module `s3-data-lake`)
All buckets: versioned, SSE-KMS, full public-access block, `BucketOwnerEnforced`, TLS-only policy,
access logging.

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `raw-<suffix>` | incoming CSVs (`raw/products|orders|order_items/`) | Std→IA@30d→Glacier@90d; EventBridge **on** |
| `lakehouse-dwh-<suffix>` | Delta tables (`dwh/...`) | Std→IA@90d; versioned (Delta history) |
| `archived-<suffix>` | source files moved post-success | →Deep Archive@1d, expire@2555d |
| `rejected-<suffix>` | invalid records + reject reports | expire@90d |
| `glue-scripts-<suffix>` | job code + `--TempDir` | versioning only |
| `athena-results-<suffix>` | query output | expire@14d |
| `access-logs-<suffix>` | S3 access logs | expire@365d |

### 4. ETL — Glue (PySpark + Delta Lake) (module `glue-jobs` + `glue/`)
- One parameterized Glue job **per dataset** (brief: "a Glue Job … for each dataset"): `${env}-products-etl`,
  `-orders-etl`, `-order_items-etl`. Glue **4.0**, `G.1X`, **VPC-attached** via an `aws_glue_connection`
  (NETWORK), `max_concurrent_runs=1`, retries + timeout.
- **Delta enablement:** `--datalake-formats delta` + Spark confs (`DeltaSparkSessionExtension`,
  `DeltaCatalog`). **No `--additional-python-modules`** needed (Delta is bundled) → jobs run fully
  in-VPC with no PyPI/internet dependency (P1 lesson #7). **`--job-bookmark-disable`** (P1 lesson #2).
- **Reusable PySpark modules** (`glue/common/`, via `--extra-py-files`):
  - `schemas.py` — explicit `StructType` per dataset (no `inferSchema` → schema enforcement).
  - `validation.py` — split valid vs. rejected; write rejects + reason to `rejected/`; log counts:
    no null PKs (`product_id`/`order_id`/`id`), parseable `order_timestamp`/`date`, referential
    integrity (`order_items.order_id ∈ orders`, `product_id ∈ products`), ranges
    (`total_amount ≥ 0`, `add_to_cart_order ≥ 0`, `reordered ∈ {0,1}`).
  - `delta_io.py` — window-dedup (PK ordered by timestamp, keep latest) + Delta **MERGE INTO** upsert
    (idempotent re-runs) + partitioning.
- **Partitioning (justified):** `orders` & `order_items` by `date` (daily; prunes time scans);
  `products` unpartitioned (small dim). PKs `product_id` / `order_id` / `id`.
- **Cost:** start at 2 `G.1X` workers; enable Glue auto-scaling; small datasets finish in one DPU-minute band.

### 5. Catalog & Analytics (modules `glue-catalog`, `athena`)
- Glue Catalog DB `${env}_lakehouse_dwh`; register the 3 Delta tables (native Delta on Athena v3).
- Optional Glue Crawler to refresh partitions (optional SFN step, per brief).
- Athena workgroup `${env}-analytics`: enforce config, CloudWatch metrics, SSE-KMS results bucket.

### 6. Orchestration — Step Functions (module `step-functions`)
- **Standard** state machine, ASL via `jsonencode`, X-Ray on. Flow:
  1. `ValidateInput` → `Choice`.
  2. **`Map`** over the 3 datasets → `glue:startJobRun.sync`, each with `Retry` (exp. backoff) +
     `Catch(States.ALL) → NotifyFailure` + `TimeoutSeconds` (brief: failure handling, timeouts, branching).
  3. All success → `ArchiveFiles` (Lambda `raw/ → archived/`).
  4. Optional `RunCrawler` / `AthenaValidate` (`StartQueryExecution`) presence check.
  5. `NotifyFailure` → SNS publish → `Fail`.

### 7. Compute — Lambdas + DLQ (module `lambda-functions`)
- **router** Lambda (VPC-attached): EventBridge event → shape payload → `states:StartExecution`.
- **archive** Lambda (VPC-attached): `raw/ → archived/` (copy+delete); **raises on partial failure**
  so SFN `Catch` alerts (P1 lesson #6).
- **SQS dead-letter queue** (SSE) + `aws_lambda_function_event_invoke_config` (bounded retries) on the
  router; EventBridge target gets `retry_policy` + `dead_letter_config` (P1 lesson #3).
- Python 3.12, least-privilege roles, KMS access, CloudWatch logs (KMS-encrypted), X-Ray.

### 8. IAM (module `iam-roles`) — least privilege
`glue-etl` (read `raw/`+scripts, write `dwh/`+`rejected/`, KMS, catalog), `lambda-router`
(`states:StartExecution` + `sqs:SendMessage` to DLQ), `lambda-archive` (read/delete `raw/`, write
`archived/`, KMS), `step-functions` (Glue start/stop, PassRole gated by `iam:PassedToService`, Lambda
invoke, SNS, Athena/catalog, X-Ray), `eventbridge` (invoke router). Scoped to specific ARNs/prefixes;
inline policies; reusable KMS action locals.

### 9. Observability (module `observability`) + auditability
- CloudWatch dashboard; alarms (threshold 0 → SNS) on SFN `ExecutionsFailed`, per-Glue `FailedRuns`,
  Lambda `Errors`, **DLQ `ApproximateNumberOfMessagesVisible > 0`**.
- SNS `${env}-lakehouse-alerts` (email subs via var).
- **CloudTrail** → KMS-encrypted log bucket (S3 data events on raw/dwh, Glue/SFN management events) for
  auditability of data movement.
- Glue continuous CloudWatch logs + metrics; SFN + Lambda X-Ray.

### 10. CI/CD (`.github/workflows/ci.yml`) — scoped to `main`
- `permissions: id-token: write`. Triggers: push/PR to `main` (+ `workflow_dispatch`), path-filtered.
- **test** job: Python 3.12, `pip install -r tests/requirements.txt`, `pytest tests/ -v`.
- **validate** job (`needs: test`): OIDC assume role → `terraform fmt -check`, `init`, `validate`,
  `plan` (PR comment). No `apply`.
- **Least-privilege CI role** (P1 lesson #5): `ReadOnlyAccess` + scoped state-backend actions; no broad
  write, no `iam:PassRole`. A future gated apply pipeline uses a separate, narrowly-scoped role.
- Secrets: `AWS_TERRAFORM_ROLE_ARN`, `AWS_ACCOUNT_ID` (from bootstrap output).

---

## Cost optimization summary (the user's explicit priority)
- **Single-AZ** networking by default; **single NAT**; interface endpoints trimmable (biggest lever).
- 100% **serverless / on-demand**: Glue (per-second DPU), Lambda, Athena (per-TB scanned), DynamoDB n/a here.
- **S3 lifecycle** transitions on every bucket; `bucket_key_enabled` to cut KMS request cost.
- **Right-sized compute**: Spark only for Delta ETL; Lambda for archiving; no idle/always-on resources.
- **Partition pruning** (date) + Delta file compaction keep Athena scan costs low.
- CI is plan-only (no apply compute); no NAT data on the steady-state path (endpoints).

---

## Brief-compliance matrix (does NOT violate the instruction PDF)

| Brief requirement (PDF) | Where it's satisfied in this plan |
|---|---|
| Detect new data in S3 raw zone | EventBridge `Object Created` rule → router Lambda (§6/§7) |
| Clean & transform with Glue + Delta Lake | Per-dataset Glue PySpark + Delta jobs (§4) |
| Write clean data to optimized Delta tables in processed zone | `lakehouse-dwh/` Delta, partitioned, `MERGE` (§3/§4) |
| Update Glue Data Catalog for Athena | `glue-catalog` module + Athena v3 native Delta (§5) |
| Archive originals after successful ingestion | archive Lambda `raw/ → archived/` (§7), `ArchiveFiles` SFN step (§6) |
| Orchestrate with Step Functions | Standard state machine, Map/Retry/Catch/Timeout (§6) |
| CI/CD on `main` (GitHub Actions) | `.github/workflows/ci.yml`, triggers scoped to `main` (§10) |
| Delta tables: dedup, schema enforcement, partitioning, merge/upsert | `validation.py` + `delta_io.py` + explicit schemas (§4) |
| Validation: no null PKs, valid timestamps, referential integrity, dedup across files; log rejected | `validation.py` → `rejected/` with reasons + counts (§4) |
| Orchestration: detect → Glue per dataset → archive → (opt) alert/crawler/Athena; failure handling/timeouts/branching | §6 state machine; SNS alert; optional crawler + Athena validate |
| CI: Spark job CI, unit/integration tests, (opt) deploy SFn def | pytest + fmt/validate/plan (§10); SFn ASL emitted by TF (optional deploy) |
| 3 datasets (products / orders / order_items) with listed fields | `schemas.py` explicit `StructType` per dataset (§4) |
| Processed Delta in a `lakehouse-dwh` zone | `lakehouse-dwh-<suffix>` bucket (§3) |

**Added (non-conflicting) requirements** — VPC/PrivateLink, KMS CMK, least-privilege IAM, CloudTrail/
CloudWatch/X-Ray, DLQ, cost controls — all layer on top of the above and remove nothing the brief asks for.

---

## Build order
1. Scaffold repo + `README`/`CLAUDE.md`; `convert_xlsx_to_csv.py`, `generate_dirty_data.py`, `upload_raw.py`.
2. `glue/common/` (`schemas`, `validation`, `delta_io`) + 3 ETL scripts.
3. `tests/` (validation, dedup, schema, router, archive) — moto/mock; openpyxl; PySpark-light pure functions.
4. Terraform `bootstrap` (state backend + scoped OIDC role).
5. Modules (P1 order): kms → networking → s3-data-lake → glue-catalog → iam-roles → glue-jobs →
   lambda-functions (+DLQ) → step-functions → eventbridge → athena → observability (+CloudTrail).
6. `envs/dev` composition + `*.tfvars.example` (single-AZ defaults).
7. Step Functions ASL (Map/Retry/Catch/Timeout + archive + optional crawler/Athena).
8. `.github/workflows/ci.yml` (scoped to main, least-priv role).
9. README design justifications + architecture diagram.

## Verification / done criteria
- `terraform fmt -check` + `validate` pass; `plan` clean.
- `pytest tests/ -v` green: null-PK/timestamp/range/referential validation, window-dedup keeps-latest +
  idempotent, schema enforcement, router StartExecution, archive fail-loud.
- Local: `generate_dirty_data.py` → rejected rows land in `rejected/` with reasons; re-run an ETL job →
  Delta MERGE produces no duplicates (idempotency).
- (With AWS) `apply`, drop a file in `raw/`, SFN succeeds, query Delta in Athena, source in `archived/`,
  a forced failure lands in the DLQ.
- CI runs on push/PR to `main` only; OIDC; plan posted to PR.

## Risks / notes
- **Delta-on-Glue-Catalog + Athena v3**: native Delta read is version-sensitive; fallback =
  symlink-manifest + crawler (documented).
- **No AWS account assumed**: CI stops at `plan`; `apply` path documented, not run until creds exist.
- **Sample data is clean**: validation/dedup only provable via the dirty-data generator (first-class deliverable).
- **Cost vs. security tradeoff is explicit**: single-AZ + trimmable interface endpoints; the cheap
  no-endpoint fallback is documented for a course-budget run.
- No AI co-author trailers in commits/PRs/docs (P1 `CLAUDE.md`).
