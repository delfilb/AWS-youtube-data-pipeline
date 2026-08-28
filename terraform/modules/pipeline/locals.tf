data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id

  bucket_names = {
    bronze  = "${local.name_prefix}-bronze-${local.account_id}"
    silver  = "${local.name_prefix}-silver-${local.account_id}"
    gold    = "${local.name_prefix}-gold-${local.account_id}"
    scripts = "${local.name_prefix}-scripts-${local.account_id}"
    athena  = "${local.name_prefix}-athena-results-${local.account_id}"
  }

  glue_db_names = {
    bronze = replace("${local.name_prefix}_bronze", "-", "_")
    silver = replace("${local.name_prefix}_silver", "-", "_")
    gold   = replace("${local.name_prefix}_gold", "-", "_")
  }

  # Repo root is three levels up from this module (terraform/modules/pipeline).
  repo_root = abspath("${path.module}/../../..")

  glue_script_paths = {
    bronze_to_silver = "${local.repo_root}/glue_jobs/bronze_to_silver_statistics.py"
    silver_to_gold   = "${local.repo_root}/glue_jobs/silver_to_gold_analytics.py"
  }
}
