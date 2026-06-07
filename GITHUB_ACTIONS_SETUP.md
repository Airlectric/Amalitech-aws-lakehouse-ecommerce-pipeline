# GitHub Actions Plan, Apply, and Destroy Setup

This project does not need long-lived AWS access keys in GitHub. It uses GitHub OIDC instead.
That means GitHub temporarily assumes an AWS IAM role only while the workflow is running.

## What the workflow does

- Pull requests into `develop` run tests and `terraform plan`.
- Merging a PR into `develop` creates a `push` to `develop`, so the workflow runs tests, plans, then automatically runs `terraform apply`.
- Manual runs can choose `plan`, `apply`, or `destroy`.
- `destroy` is manual only. It never runs from a PR or merge.

## GitHub repository secrets

Create these secrets in GitHub: `Settings` -> `Secrets and variables` -> `Actions`.

```text
AWS_ACCOUNT_ID=108782069549
P2_AWS_TERRAFORM_PLAN_ROLE_ARN=arn:aws:iam::108782069549:role/dev-lakehouse-github-actions
P2_AWS_TERRAFORM_APPLY_ROLE_ARN=arn:aws:iam::108782069549:role/dev-lakehouse-github-actions-apply
P2_TF_STATE_BUCKET=lakehouse-ecommerce-tfstate-108782069549
P2_TF_LOCK_TABLE=lakehouse-terraform-state-lock
P2_TF_STATE_KMS_KEY_ARN=arn:aws:kms:us-east-1:108782069549:key/8a663955-76f3-4c8d-8c14-1796bf3e7ad4
```

## GitHub environment

Create a GitHub Environment named exactly:

```text
dev
```

The AWS apply role trusts the GitHub OIDC subject `environment:dev`, so this environment must exist.
For this solo test project it can have no required reviewers. Add reviewers later if you want apply or destroy to pause for approval.

## Running manually

Go to `Actions` -> `CI/CD` -> `Run workflow` on the `develop` branch.

Choose one:

```text
plan     Preview changes only.
apply    Apply the saved plan to AWS.
destroy  Destroy the dev infrastructure. Manual only.
```

## AWS setup order

Bootstrap has already created the plan/apply roles. If you ever recreate the AWS account setup, run:

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output github_actions_plan_role_arn
terraform output github_actions_apply_role_arn
```
