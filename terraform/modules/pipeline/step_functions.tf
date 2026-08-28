resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = aws_iam_role.step_functions.arn
  tags     = var.tags

  definition = templatefile("${path.module}/templates/state_machine.json.tftpl", {
    ingestion_lambda_arn       = aws_lambda_function.youtube_ingestion.arn
    json_to_parquet_lambda_arn = aws_lambda_function.json_to_parquet.arn
    data_quality_lambda_arn    = aws_lambda_function.data_quality.arn
    bronze_to_silver_job_name  = aws_glue_job.bronze_to_silver.name
    silver_to_gold_job_name    = aws_glue_job.silver_to_gold.name
    bronze_database            = aws_glue_catalog_database.bronze.name
    silver_database            = aws_glue_catalog_database.silver.name
    gold_database              = aws_glue_catalog_database.gold.name
    silver_bucket              = aws_s3_bucket.this["silver"].id
    gold_bucket                = aws_s3_bucket.this["gold"].id
    sns_topic_arn              = aws_sns_topic.alerts.arn
  })
}
