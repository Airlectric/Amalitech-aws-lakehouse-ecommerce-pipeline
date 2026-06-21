# Production Readiness Audit — Lakehouse Architecture (Project 2)

**Date:** 2026-06-21  
**Branch audited:** `feat/stage0-catalog-fix-and-testability`

This document records the tiered gap analysis performed against the original implementation and
tracks the status of each item.

---

## Tier 0 — Critical (correctness / silent failure)

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 0a | **Glue Catalog schema mismatch** — all three `aws_glue_catalog_table` column blocks were fictional placeholders unrelated to the actual `schemas.py` definitions. Athena consumers got wrong/empty columns. | Critical | **Fixed** (commit `0a`) |
| 0b | **ETL not testable** — `getResolvedOptions` imported at module level, blocking `import` of common modules in pytest without the Glue runtime. | High | **Fixed** (commit `0b`) — moved inside `main()` |
| 0c | **`lambda` reserved keyword in package path** — `lambda/handlers/__init__.py` declared an importable package at a Python reserved keyword; the directory was renamed to `src/lambda_functions/`. | High | **Fixed** (commit `0c`) |

---

## Tier 1 — Correctness and brief compliance

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1a | **Referential integrity not enforced** — `order_items.order_id` and `order_items.product_id` FK checks were absent despite being a brief validation requirement. Orphan rows merged silently into the Delta table. | High | **Fixed** (commit `1a`) — anti-join against parent Delta tables; orphans routed to `rejected/` |
| 1b | **No empty-file guard** — a zero-row CSV triggered a merge of nothing with no observable signal. Schema-drift and post-MERGE reconciliation were also absent. | Medium | **Fixed** (commit `1b`) — `isEmpty()` check, header comparison, post-MERGE row-count assertion |
| 1c | **DQ metrics print-only** — rejection counts were logged to stdout only; no CloudWatch metrics, so alarms could not be built. | Medium | **Fixed** (commit `1c`) — `PutMetricData` to `Lakehouse/DQ` namespace; scoped IAM |
| 1d | **Tests incomplete / CI skips Spark suite** — `test_validation.py` ignored, no Spark integration tests, no Java in CI. | Medium | **Fixed** (commit `1d`) — 14 `@pytest.mark.spark` integration tests; Java 11 in CI |
| 2d | **CI missing `main` branch trigger** — brief requires CI on `main`; only `develop` was wired. | Low | **Fixed** (within commit `1d`) |

---

## Tier 2 — Operations, observability, lakehouse maintenance

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 2a | **No Delta table maintenance** — OPTIMIZE/VACUUM never ran; small-file accumulation and unbounded version history over time. | Medium | **Fixed** (commit `2a`) — daily `maintenance_etl.py` Glue job via EventBridge Scheduler |
| 2b | **Alarms incomplete** — no SLA freshness alarm, no DQ rejection-rate alarm, no X-Ray active tracing on Lambdas. | Medium | **Fixed** (commit `2b`) — SFN SLA alarm, per-dataset DQ rejection-rate alarm, Lambda `Active` tracing, X-Ray IAM |
| 2c | **No row-level lineage** — rows were not traceable to the SFN execution or upload time. | Low | **Fixed** (commit `2c`) — `ingested_at` and `source_execution_id` stamped on all Delta rows and catalog schemas |
| 2e | **No runbooks or DLQ replay tooling** — no documented triage procedure, backfill process, schema evolution steps, or DR stance. | Medium | **Fixed** (commit `2e`) — `docs/runbooks.md` + `scripts/replay_dlq.py` |

---

## Tier 3 — Scale and cost

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 3a | **Glue jobs hardcoded sizing** — worker type and count were constants; auto-scaling off; timeout flat 60 min. | Low | **Fixed** (commit `3a`) — `--enable-auto-scaling`; `worker_type`/`worker_count`/`timeout_minutes` variables; ceiling raised to 10 workers |
| 3b | **No Athena scan limit** — full-table scans could scan unlimited data at $5/TB; no per-query guardrail. | Low | **Fixed** (commit `3b`) — `bytes_scanned_cutoff_per_query = 10 GiB` on the analytics workgroup |

---

## Tier 4 — Security and governance

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 4a | **CloudTrail logs bucket missing SSE-KMS** — the trail itself used the CMK (`kms_key_id`), but the S3 bucket received SSE-S3 by default; not at CMK-level at-rest encryption end-to-end. | Low | **Fixed** (commit `4a`) — `aws_s3_bucket_server_side_encryption_configuration` with the project CMK |
| 4b | **No S3 object tagging convention** — no documented or enforced object tag strategy for cost allocation, access control, or retention management. | Low | **Fixed** (commit `4b`) — tagging convention documented in `docs/runbooks.md §6` |

---

## Tier 5 — Documentation

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 5a | **Stale planning doc** — `Dannys_notes/project_plan.md` described a VPC-attached Lambda and Glue topology that was not implemented. | Low | **Fixed** — as-built note added |
| 5b | **No Delta time-travel example** — README lacked a concrete analyst-facing query to leverage Delta's time-travel for troubleshooting. | Low | **Fixed** — example added to README |
| 5c | **No production hardening summary** — README did not reference the audit or the runbooks. | Low | **Fixed** — hardening section added to README |

---

## Known limitations (out of scope for this hardening pass)

- **VPC / PrivateLink**: The dev architecture is fully serverless without a VPC. A production
  deployment should consider VPC endpoints for Glue, Step Functions, KMS, and CloudWatch to
  eliminate internet-routable paths.
- **Cross-region replication**: No S3 cross-region replication is configured. For geographic
  redundancy, enable CRR on the raw and DWH buckets.
- **Lake Formation**: Column-level and row-level access control requires Lake Formation on top of
  the existing Glue Catalog. Not implemented.
- **Partition retention**: Old date partitions in `orders`/`order_items` are not automatically
  dropped. The daily VACUUM frees the underlying storage but Glue Catalog partition metadata
  accumulates. A periodic `MSCK REPAIR TABLE` or Glue crawler pass is needed for large
  partition counts.
- **Multi-AZ**: The current single-AZ default is intentional for cost. A production deployment
  should configure multi-AZ NAT (if VPC is added) and consider Glue job multi-AZ availability.
