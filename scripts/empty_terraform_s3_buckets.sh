#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd aws
need_cmd jq
need_cmd terraform

printf 'Reading Terraform state for managed S3 buckets...\n'
state_json="$(terraform state pull)"

mapfile -t buckets < <(
  printf '%s' "${state_json}" |
    jq -r '
      .resources[]?
      | select(.type == "aws_s3_bucket")
      | .instances[]?
      | (.attributes.bucket // .attributes.id // empty)
    ' |
    sort -u
)

if [ "${#buckets[@]}" -eq 0 ]; then
  printf 'No Terraform-managed S3 buckets found in state.\n'
  exit 0
fi

for bucket in "${buckets[@]}"; do
  if ! aws s3api head-bucket --bucket "${bucket}" --region "${REGION}" >/dev/null 2>&1; then
    printf 'Skipping missing bucket: %s\n' "${bucket}"
    continue
  fi

  printf 'Suspending versioning and emptying bucket: %s\n' "${bucket}"
  aws s3api put-bucket-versioning \
    --bucket "${bucket}" \
    --versioning-configuration Status=Suspended \
    --region "${REGION}" >/dev/null 2>&1 || true

  aws s3 rm "s3://${bucket}" --recursive --region "${REGION}" >/dev/null 2>&1 || true

  while true; do
    versions_json="$(
      aws s3api list-object-versions \
        --bucket "${bucket}" \
        --max-items 1000 \
        --region "${REGION}" \
        --output json
    )"
    delete_json="$(
      printf '%s' "${versions_json}" |
        jq -c '{
          Objects: (((.Versions // []) + (.DeleteMarkers // [])) | map({Key, VersionId})),
          Quiet: true
        }'
    )"
    delete_count="$(printf '%s' "${delete_json}" | jq '.Objects | length')"

    if [ "${delete_count}" -eq 0 ]; then
      break
    fi

    aws s3api delete-objects \
      --bucket "${bucket}" \
      --delete "${delete_json}" \
      --region "${REGION}" >/dev/null
    printf 'Deleted %s object versions/delete markers from %s\n' "${delete_count}" "${bucket}"
  done

  printf 'Bucket is empty: %s\n' "${bucket}"
done
