#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/terraform/bootstrap"
DEV_DIR="${ROOT_DIR}/terraform/envs/dev"
DATA_DIR="${ROOT_DIR}/Data"

COMMAND="${1:-all}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
UPLOAD_VARIANT="${UPLOAD_VARIANT:-clean}"
POST_UPLOAD_SLEEP_SECONDS="${POST_UPLOAD_SLEEP_SECONDS:-20}"
TF_STATE_KEY="${TF_STATE_KEY:-terraform/dev/terraform.tfstate}"
LOCK_TABLE_NAME="${TF_LOCK_TABLE:-lakehouse-terraform-state-lock}"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/aws_e2e.sh [command]

Commands:
  prepare       Convert XLSX files to CSV and verify local raw files exist.
  dirty         Run prepare, then generate Data/dirty files.
  bootstrap     Apply terraform/bootstrap using the default AWS account.
  plan          Run prepare, initialize dev backend, validate, and terraform plan.
  deploy        Run prepare, bootstrap, initialize dev backend, validate, and apply.
  upload-clean  Upload clean CSVs to the deployed raw bucket.
  upload-dirty  Generate and upload dirty CSVs to the deployed raw bucket.
  all           Run prepare, bootstrap, deploy, then upload based on UPLOAD_VARIANT.

Environment:
  AWS_REGION or AWS_DEFAULT_REGION   AWS region, default us-east-1.
  AWS_PROFILE                        Optional; otherwise AWS CLI default account is used.
  GITHUB_REPO                        owner/repo, needed only if bootstrap secrets file is absent.
  ALERT_EMAILS                       Comma-separated SNS email list for generated dev tfvars.
  AUTO_APPROVE=true                  Pass -auto-approve to terraform apply.
  UPLOAD_VARIANT=clean|dirty|both|none  Upload behavior for the all command.
  TF_STATE_BUCKET                    Override generated state bucket name if backend config is absent.
  TF_LOCK_TABLE                      Override lock table name, default lakehouse-terraform-state-lock.
  TF_STATE_KMS_KEY_ARN               Override state KMS key ARN if backend config is absent.
  TF_STATE_KEY                       Remote state key, default terraform/dev/terraform.tfstate.
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

python_bin() {
  if command -v python3 >/dev/null 2>&1; then
    printf 'python3'
  elif command -v python >/dev/null 2>&1; then
    printf 'python'
  else
    fail "Required command not found: python3 or python"
  fi
}

terraform_apply_args() {
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    printf '%s\n' '-auto-approve'
  fi
}

aws_account_id() {
  aws sts get-caller-identity \
    --query Account \
    --output text \
    --region "${AWS_REGION}"
}

hcl_email_list() {
  local emails="${ALERT_EMAILS:-}"
  if [[ -z "${emails// /}" ]]; then
    printf '[]'
    return
  fi

  local result="["
  local first="true"
  local item
  IFS=',' read -ra items <<< "${emails}"
  for item in "${items[@]}"; do
    item="${item// /}"
    [[ -z "${item}" ]] && continue
    if [[ "${first}" != "true" ]]; then
      result+=", "
    fi
    result+="\"${item}\""
    first="false"
  done
  result+="]"
  printf '%s' "${result}"
}

prepare_data() {
  local py
  py="$(python_bin)"

  log "Preparing local CSV inputs"
  "${py}" "${ROOT_DIR}/scripts/convert_xlsx_to_csv.py" --data-dir "${DATA_DIR}"

  local missing=0
  for file in products.csv orders_apr_2025.csv order_items_apr_2025.csv; do
    if [[ ! -f "${DATA_DIR}/${file}" ]]; then
      printf 'Missing required CSV: %s\n' "${DATA_DIR}/${file}" >&2
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]] || fail "Local data preparation did not produce every required CSV."
}

prepare_dirty_data() {
  local py
  py="$(python_bin)"

  prepare_data
  log "Generating dirty data inputs"
  "${py}" "${ROOT_DIR}/scripts/generate_dirty_data.py" --data-dir "${DATA_DIR}"

  local missing=0
  for file in dirty_products.csv dirty_orders.csv dirty_order_items.csv; do
    if [[ ! -f "${DATA_DIR}/dirty/${file}" ]]; then
      printf 'Missing required dirty CSV: %s\n' "${DATA_DIR}/dirty/${file}" >&2
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]] || fail "Dirty data generation did not produce every required CSV."
}

ensure_aws_tools() {
  need_cmd aws
  need_cmd terraform
}

ensure_default_account() {
  local account
  account="$(aws_account_id)"
  [[ -n "${account}" && "${account}" != "None" ]] || fail "Could not resolve AWS account from default credentials."
  log "Using AWS account ${account} in ${AWS_REGION}"
  printf '%s' "${account}"
}

ensure_github_oidc_provider_exists() {
  local account="$1"
  local provider_arn="arn:aws:iam::${account}:oidc-provider/token.actions.githubusercontent.com"

  if aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "${provider_arn}" \
    --region "${AWS_REGION}" >/dev/null 2>&1; then
    return
  fi

  fail "GitHub OIDC provider is missing in this AWS account. Project 2 bootstrap references it as an existing account-level provider. Run Project 1 bootstrap first, or create/import token.actions.githubusercontent.com before running Project 2 bootstrap."
}

write_bootstrap_tfvars_if_missing() {
  local account="$1"
  local state_bucket="${TF_STATE_BUCKET:-lakehouse-ecommerce-tfstate-${account}}"

  if [[ ! -f "${BOOTSTRAP_DIR}/terraform.tfvars" ]]; then
    log "Creating terraform/bootstrap/terraform.tfvars"
    cat > "${BOOTSTRAP_DIR}/terraform.tfvars" <<EOF
environment     = "${ENVIRONMENT}"
aws_region      = "${AWS_REGION}"
lock_table_name = "${LOCK_TABLE_NAME}"
EOF
  fi

  if [[ ! -f "${BOOTSTRAP_DIR}/secrets.auto.tfvars" ]]; then
    [[ -n "${GITHUB_REPO:-}" ]] || fail "GITHUB_REPO is required because terraform/bootstrap/secrets.auto.tfvars is absent."
    log "Creating terraform/bootstrap/secrets.auto.tfvars"
    cat > "${BOOTSTRAP_DIR}/secrets.auto.tfvars" <<EOF
state_bucket_name = "${state_bucket}"
github_repo       = "${GITHUB_REPO}"
EOF
  fi
}

bootstrap_backend() {
  ensure_aws_tools
  local account
  account="$(ensure_default_account)"
  ensure_github_oidc_provider_exists "${account}"
  write_bootstrap_tfvars_if_missing "${account}"

  log "Initializing terraform/bootstrap"
  terraform -chdir="${BOOTSTRAP_DIR}" init

  log "Applying terraform/bootstrap"
  mapfile -t args < <(terraform_apply_args)
  terraform -chdir="${BOOTSTRAP_DIR}" apply "${args[@]}"
}

write_backend_config_if_missing() {
  if [[ -f "${DEV_DIR}/backend-dev.hcl" ]]; then
    return
  fi

  local bucket="${TF_STATE_BUCKET:-}"
  local table="${TF_LOCK_TABLE:-}"
  local kms_key="${TF_STATE_KMS_KEY_ARN:-}"

  if [[ -z "${bucket}" ]]; then
    bucket="$(terraform -chdir="${BOOTSTRAP_DIR}" output -raw state_bucket_id 2>/dev/null || true)"
  fi
  if [[ -z "${table}" ]]; then
    table="$(terraform -chdir="${BOOTSTRAP_DIR}" output -raw lock_table_id 2>/dev/null || true)"
  fi
  if [[ -z "${kms_key}" ]]; then
    kms_key="$(terraform -chdir="${BOOTSTRAP_DIR}" output -raw kms_key_arn 2>/dev/null || true)"
  fi

  [[ -n "${bucket}" ]] || fail "Cannot create backend-dev.hcl: missing TF_STATE_BUCKET and bootstrap output state_bucket_id."
  [[ -n "${table}" ]] || fail "Cannot create backend-dev.hcl: missing TF_LOCK_TABLE and bootstrap output lock_table_id."

  log "Creating terraform/envs/dev/backend-dev.hcl"
  {
    printf 'bucket         = "%s"\n' "${bucket}"
    printf 'key            = "%s"\n' "${TF_STATE_KEY}"
    printf 'region         = "%s"\n' "${AWS_REGION}"
    printf 'dynamodb_table = "%s"\n' "${table}"
    printf 'encrypt        = true\n'
    if [[ -n "${kms_key}" ]]; then
      printf 'kms_key_id     = "%s"\n' "${kms_key}"
    fi
  } > "${DEV_DIR}/backend-dev.hcl"
}

write_dev_tfvars_if_missing() {
  local account="$1"
  if [[ -f "${DEV_DIR}/terraform.tfvars" ]]; then
    return
  fi

  log "Creating terraform/envs/dev/terraform.tfvars"
  cat > "${DEV_DIR}/terraform.tfvars" <<EOF
environment          = "${ENVIRONMENT}"
aws_region           = "${AWS_REGION}"
vpc_cidr             = "10.0.0.0/16"
availability_zone    = "${AWS_REGION}a"
public_subnet_cidr   = "10.0.0.0/24"
private_subnet_cidr  = "10.0.10.0/24"
isolated_subnet_cidr = "10.0.20.0/24"
bucket_suffix        = "${account}"
alert_emails         = $(hcl_email_list)
EOF
}

init_dev() {
  ensure_aws_tools
  local account
  account="$(ensure_default_account)"
  write_backend_config_if_missing
  write_dev_tfvars_if_missing "${account}"

  log "Initializing terraform/envs/dev"
  terraform -chdir="${DEV_DIR}" init -backend-config="${DEV_DIR}/backend-dev.hcl"

  log "Validating terraform/envs/dev"
  terraform -chdir="${DEV_DIR}" validate
}

plan_dev() {
  prepare_data
  init_dev
  log "Planning terraform/envs/dev"
  terraform -chdir="${DEV_DIR}" plan -out=tfplan
}

deploy_dev() {
  prepare_data
  bootstrap_backend
  init_dev

  log "Applying terraform/envs/dev"
  mapfile -t args < <(terraform_apply_args)
  terraform -chdir="${DEV_DIR}" apply "${args[@]}"
}

raw_bucket_id() {
  terraform -chdir="${DEV_DIR}" output -raw raw_bucket_id
}

state_machine_arn() {
  terraform -chdir="${DEV_DIR}" output -raw step_functions_arn
}

upload_clean() {
  ensure_aws_tools
  local py bucket
  py="$(python_bin)"
  bucket="$(raw_bucket_id)"

  prepare_data
  log "Uploading clean raw data to ${bucket}"
  "${py}" "${ROOT_DIR}/scripts/upload_raw.py" \
    --bucket "${bucket}" \
    --data-dir "${DATA_DIR}" \
    --variant clean \
    --region "${AWS_REGION}"
  show_recent_executions
}

upload_dirty() {
  ensure_aws_tools
  local py bucket
  py="$(python_bin)"
  bucket="$(raw_bucket_id)"

  prepare_dirty_data
  log "Uploading dirty raw data to ${bucket}"
  "${py}" "${ROOT_DIR}/scripts/upload_raw.py" \
    --bucket "${bucket}" \
    --data-dir "${DATA_DIR}/dirty" \
    --variant dirty \
    --region "${AWS_REGION}"
  show_recent_executions
}

show_recent_executions() {
  local sfn
  sfn="$(state_machine_arn 2>/dev/null || true)"
  [[ -n "${sfn}" ]] || return

  if [[ "${POST_UPLOAD_SLEEP_SECONDS}" != "0" ]]; then
    log "Waiting ${POST_UPLOAD_SLEEP_SECONDS}s for EventBridge/Lambda to start executions"
    sleep "${POST_UPLOAD_SLEEP_SECONDS}"
  fi

  log "Recent Step Functions executions"
  aws stepfunctions list-executions \
    --state-machine-arn "${sfn}" \
    --max-results 10 \
    --query 'executions[].{name:name,status:status,startDate:startDate,stopDate:stopDate}' \
    --output table \
    --region "${AWS_REGION}" || true
}

run_all_uploads() {
  case "${UPLOAD_VARIANT}" in
    clean) upload_clean ;;
    dirty) upload_dirty ;;
    both) upload_clean; upload_dirty ;;
    none) log "Skipping upload because UPLOAD_VARIANT=none" ;;
    *) fail "UPLOAD_VARIANT must be one of: clean, dirty, both, none" ;;
  esac
}

case "${COMMAND}" in
  prepare) prepare_data ;;
  dirty) prepare_dirty_data ;;
  bootstrap) bootstrap_backend ;;
  plan) plan_dev ;;
  deploy) deploy_dev ;;
  upload-clean) upload_clean ;;
  upload-dirty) upload_dirty ;;
  all) deploy_dev; run_all_uploads ;;
  -h|--help|help) usage ;;
  *) usage; fail "Unknown command: ${COMMAND}" ;;
esac
