# A dedicated workgroup (rather than managing the account's built-in "primary"
# workgroup, which already exists as a singleton and can't be freshly
# "created" by Terraform) that the data-quality Lambda targets via the
# ATHENA_WORKGROUP environment variable, giving it a query-results
# destination without relying on account-level defaults.

resource "aws_athena_workgroup" "pipeline" {
  name  = "${local.name_prefix}-athena"
  state = "ENABLED"
  tags  = var.tags

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.this["athena"].id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
