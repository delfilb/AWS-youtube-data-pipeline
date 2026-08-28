# Terraform — YouTube Trending Data Pipeline

Provisions everything currently listed in the top-level [README](../README.md) —
S3 buckets, Glue Data Catalog + jobs + crawler, the three Lambdas, the Step
Functions state machine, EventBridge schedule, SNS topic, and Athena workgroup
— as code.

This is a **fresh, new-name deployment**: it does not touch or import the
resources you already created by hand in the AWS Console (`aws-yt-data-pipeline-*`
in account `<ACCOUNT_ID>`). Once you've validated the Terraform-managed stack,
decommission the manual resources yourself.

## Layout

```
terraform/
├── bootstrap/        # one-time: S3 bucket + DynamoDB table for remote state
├── modules/pipeline/  # all pipeline resources, parametrized by environment
└── envs/dev/          # dev environment: backend + provider + module call
```

To add another environment (e.g. `prod`), copy `envs/dev` to `envs/prod`,
change the backend `key` and the `environment` passed into the module.

## 1. Bootstrap remote state (once per AWS account)

```bash
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

Note the `state_bucket_name` and `lock_table_name` outputs.

## 2. Configure the dev environment

```bash
cd ../envs/dev
cp backend.hcl.example backend.hcl        # fill in the bootstrap outputs
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- `youtube_api_key` — from the [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
- `alert_email` — where pipeline success/failure alerts should go (SNS will
  send a confirmation email you must click)
- `pandas_layer_arn` — the AWS-managed "AWS SDK for pandas" layer ARN for
  your region/runtime (used by the `json-to-parquet` and `data-quality`
  Lambdas for pandas + awswrangler). Look up the current version at
  https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html

`backend.hcl` and `terraform.tfvars` contain account-specific values and a
secret API key — both are gitignored; don't commit them.

## 3. Deploy

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

This creates, among other things, a Glue crawler that keeps the Bronze
`raw_statistics` table's schema/partitions current (see `modules/pipeline/glue.tf`
for why: Silver and Gold tables register themselves at write time via
`enableUpdateCatalog`/awswrangler, but Bronze needs discovery since raw JSON
lands there directly from the ingestion Lambda).

## 4. Verify

- Manually start the crawler once (`aws glue start-crawler --name <name>` from
  `terraform output`) so `raw_statistics` exists before the first ETL run, or
  just wait for its schedule.
- Trigger a manual pipeline run: `aws stepfunctions start-execution --state-machine-arn $(terraform output -raw state_machine_arn)`
- Watch it in the Step Functions console, and confirm SNS delivers the
  completion email.

## Notes / deliberate deviations from the manual setup

- **Naming**: resources are named `<project_name>-<environment>-...` with an
  account-id suffix on bucket names for global-uniqueness, not the original
  `aws-yt-data-pipeline-*` / `<ACCOUNT_ID>` names — this is a fresh stack, not
  an adoption of the old one.
- **Athena workgroup**: rather than managing the account's built-in `primary`
  workgroup (a singleton Terraform can't freshly "create"), a dedicated
  `<name_prefix>-athena` workgroup is created, and the data-quality Lambda
  was given a one-line change (`ATHENA_WORKGROUP` env var, defaults to
  `primary`) so it targets it. See `lambdas/data-quality/lambda_function.py`.
- **Lambda IAM roles** are scoped per-function to only what that function's
  code touches (Bronze write for ingestion, Silver read/write + Glue catalog
  for json-to-parquet, Silver read + Athena for data-quality) rather than one
  shared broad execution role.
- **State machine definition** is templated (`modules/pipeline/templates/state_machine.json.tftpl`)
  from the original `step_functions/pipeline_orchestation.json`, with the
  hardcoded ARNs/account id/bucket names replaced by Terraform-managed values.
- The YouTube API key is stored as a plain Lambda environment variable
  (matching the original design). For production hardening, consider moving
  it to AWS Secrets Manager or SSM Parameter Store (SecureString) and having
  the Lambda fetch it at runtime instead.
