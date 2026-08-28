# ── Deployment packages ─────────────────────────────────────────────────────────
# Each Lambda ships as a single-file zip; pandas/awswrangler come from the
# shared AWS-managed layer (var.pandas_layer_arn) instead of being bundled.

data "archive_file" "youtube_ingestion" {
  type        = "zip"
  source_file = "${local.repo_root}/lambdas/youtube_ingestion/lambda_function.py"
  output_path = "${path.module}/build/youtube-ingestion.zip"
}

data "archive_file" "json_to_parquet" {
  type        = "zip"
  source_file = "${local.repo_root}/lambdas/json_to_parquet/lambda_function.py"
  output_path = "${path.module}/build/json-to-parquet.zip"
}

data "archive_file" "data_quality" {
  type        = "zip"
  source_file = "${local.repo_root}/data_quality/dq_lambda.py"
  output_path = "${path.module}/build/data-quality.zip"
}

# ── Ingestion Lambda (Bronze) ────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "youtube_ingestion" {
  name              = "/aws/lambda/${local.name_prefix}-youtube-ingestion"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "youtube_ingestion" {
  function_name = "${local.name_prefix}-youtube-ingestion"
  role          = aws_iam_role.lambda_ingestion.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  tags          = var.tags

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_mb
  }

  filename         = data.archive_file.youtube_ingestion.output_path
  source_code_hash = data.archive_file.youtube_ingestion.output_base64sha256

  environment {
    variables = {
      YOUTUBE_API_KEY     = var.youtube_api_key
      S3_BUCKET_BRONZE    = aws_s3_bucket.this["bronze"].id
      YOUTUBE_REGIONS     = join(",", var.youtube_regions)
      SNS_ALERT_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.youtube_ingestion]
}

# ── Reference data transform Lambda (Bronze -> Silver) ───────────────────────────

resource "aws_cloudwatch_log_group" "json_to_parquet" {
  name              = "/aws/lambda/${local.name_prefix}-json-to-parquet"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "json_to_parquet" {
  function_name = "${local.name_prefix}-json-to-parquet"
  role          = aws_iam_role.lambda_json_to_parquet.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  layers        = [var.pandas_layer_arn]
  tags          = var.tags

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_mb
  }

  filename         = data.archive_file.json_to_parquet.output_path
  source_code_hash = data.archive_file.json_to_parquet.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_SILVER     = aws_s3_bucket.this["silver"].id
      S3_BUCKET_BRONZE     = aws_s3_bucket.this["bronze"].id
      GLUE_DB_SILVER       = aws_glue_catalog_database.silver.name
      GLUE_TABLE_REFERENCE = "clean_reference_data"
      SNS_ALERT_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.json_to_parquet]
}

# No aws_lambda_permission for S3 here on purpose — json_to_parquet is invoked by
# Step Functions (see the state-machine IAM role), not by a bucket notification.

# ── Data quality gate Lambda (invoked by Step Functions) ─────────────────────────

resource "aws_cloudwatch_log_group" "data_quality" {
  name              = "/aws/lambda/${local.name_prefix}-data-quality"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "data_quality" {
  function_name = "${local.name_prefix}-data-quality"
  role          = aws_iam_role.lambda_data_quality.arn
  handler       = "dq_lambda.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  layers        = [var.pandas_layer_arn]
  tags          = var.tags

  ephemeral_storage {
    size = var.lambda_ephemeral_storage_mb
  }

  filename         = data.archive_file.data_quality.output_path
  source_code_hash = data.archive_file.data_quality.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_SILVER             = aws_s3_bucket.this["silver"].id
      SNS_ALERT_TOPIC_ARN          = aws_sns_topic.alerts.arn
      DQ_MIN_ROW_COUNT             = tostring(var.dq_min_row_count)
      DQ_MAX_NULL_PERCENT          = tostring(var.dq_max_null_percent)
      DQ_FRESHNESS_HOURS           = tostring(var.dq_freshness_hours)
      DQ_REFERENCE_FRESHNESS_HOURS = tostring(var.dq_reference_freshness_hours)
      ATHENA_WORKGROUP             = aws_athena_workgroup.pipeline.name
      ATHENA_OUTPUT_LOCATION       = "s3://${aws_s3_bucket.this["athena"].id}/query-results/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.data_quality]
}
