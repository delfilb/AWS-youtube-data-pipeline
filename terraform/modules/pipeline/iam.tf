# ══════════════════════════════════════════════════════════════════════════════
# Assume-role (trust) policies, one per AWS service that needs to act as this
# pipeline's roles.
# ══════════════════════════════════════════════════════════════════════════════

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Ingestion Lambda: writes raw JSON to Bronze, publishes failure alerts.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_ingestion" {
  name               = "${local.name_prefix}-lambda-ingestion"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_ingestion" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.youtube_ingestion.arn}:*"]
  }

  statement {
    sid       = "WriteBronze"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this["bronze"].arn}/youtube/*"]
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_ingestion" {
  name   = "${local.name_prefix}-lambda-ingestion"
  role   = aws_iam_role.lambda_ingestion.id
  policy = data.aws_iam_policy_document.lambda_ingestion.json
}

# ══════════════════════════════════════════════════════════════════════════════
# json-to-parquet Lambda: reads Bronze reference JSON, writes Silver parquet +
# registers/updates the Glue catalog table (awswrangler).
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_json_to_parquet" {
  name               = "${local.name_prefix}-lambda-json-to-parquet"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_json_to_parquet" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.json_to_parquet.arn}:*"]
  }

  statement {
    sid       = "ReadBronze"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this["bronze"].arn}/youtube/*"]
  }

  statement {
    sid       = "ListBronzeBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this["bronze"].arn]
  }

  statement {
    sid = "ReadWriteSilver"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.this["silver"].arn}/*"]
  }

  statement {
    sid       = "ListSilverBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this["silver"].arn]
  }

  statement {
    sid = "SilverCatalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
      "glue:BatchUpdatePartition",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
      aws_glue_catalog_database.silver.arn,
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.silver.name}/*",
    ]
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_json_to_parquet" {
  name   = "${local.name_prefix}-lambda-json-to-parquet"
  role   = aws_iam_role.lambda_json_to_parquet.id
  policy = data.aws_iam_policy_document.lambda_json_to_parquet.json
}

# ══════════════════════════════════════════════════════════════════════════════
# data-quality Lambda: runs Athena queries against Silver tables.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "lambda_data_quality" {
  name               = "${local.name_prefix}-lambda-data-quality"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_data_quality" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.data_quality.arn}:*"]
  }

  statement {
    sid       = "ReadSilver"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.this["silver"].arn, "${aws_s3_bucket.this["silver"].arn}/*"]
  }

  statement {
    sid = "AthenaResultsBucket"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this["athena"].arn, "${aws_s3_bucket.this["athena"].arn}/*"]
  }

  statement {
    sid = "SilverCatalogRead"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
      aws_glue_catalog_database.silver.arn,
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.silver.name}/*",
    ]
  }

  statement {
    sid = "Athena"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]
    resources = [aws_athena_workgroup.pipeline.arn]
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "lambda_data_quality" {
  name   = "${local.name_prefix}-lambda-data-quality"
  role   = aws_iam_role.lambda_data_quality.id
  policy = data.aws_iam_policy_document.lambda_data_quality.json
}

# ══════════════════════════════════════════════════════════════════════════════
# Glue ETL jobs (bronze_to_silver, silver_to_gold): read/write across all three
# data lake layers and manage their own catalog tables/partitions.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "glue_job" {
  name               = "${local.name_prefix}-glue-job"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "glue_job" {
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws-glue/*"]
  }

  statement {
    sid     = "ReadBronzeAndScripts"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.this["bronze"].arn, "${aws_s3_bucket.this["bronze"].arn}/*",
      aws_s3_bucket.this["scripts"].arn, "${aws_s3_bucket.this["scripts"].arn}/*",
    ]
  }

  statement {
    sid = "ReadWriteSilverAndGold"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.this["silver"].arn, "${aws_s3_bucket.this["silver"].arn}/*",
      aws_s3_bucket.this["gold"].arn, "${aws_s3_bucket.this["gold"].arn}/*",
    ]
  }

  statement {
    sid = "Catalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
      "glue:BatchUpdatePartition",
      "glue:BatchDeletePartition",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
      aws_glue_catalog_database.bronze.arn,
      aws_glue_catalog_database.silver.arn,
      aws_glue_catalog_database.gold.arn,
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.bronze.name}/*",
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.silver.name}/*",
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.gold.name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_job" {
  name   = "${local.name_prefix}-glue-job"
  role   = aws_iam_role.glue_job.id
  policy = data.aws_iam_policy_document.glue_job.json
}

# ══════════════════════════════════════════════════════════════════════════════
# Glue crawler: discovers the Bronze raw_statistics schema + partitions.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "glue_crawler" {
  name               = "${local.name_prefix}-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "glue_crawler" {
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws-glue/*"]
  }

  statement {
    sid       = "ReadBronze"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.this["bronze"].arn, "${aws_s3_bucket.this["bronze"].arn}/*"]
  }

  statement {
    sid = "Catalog"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
      "glue:BatchUpdatePartition",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${local.account_id}:catalog",
      aws_glue_catalog_database.bronze.arn,
      "arn:aws:glue:${var.aws_region}:${local.account_id}:table/${aws_glue_catalog_database.bronze.name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_crawler" {
  name   = "${local.name_prefix}-glue-crawler"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_crawler.json
}

# ══════════════════════════════════════════════════════════════════════════════
# Step Functions state machine: invokes the three Lambdas, starts the two Glue
# jobs (sync), and publishes SNS notifications.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "step_functions" {
  name               = "${local.name_prefix}-step-functions"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "step_functions" {
  statement {
    sid     = "InvokeLambdas"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.youtube_ingestion.arn,
      aws_lambda_function.json_to_parquet.arn,
      aws_lambda_function.data_quality.arn,
    ]
  }

  statement {
    sid = "RunGlueJobs"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = [
      aws_glue_job.bronze_to_silver.arn,
      aws_glue_job.silver_to_gold.arn,
    ]
  }

  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
}

resource "aws_iam_role_policy" "step_functions" {
  name   = "${local.name_prefix}-step-functions"
  role   = aws_iam_role.step_functions.id
  policy = data.aws_iam_policy_document.step_functions.json
}

# ══════════════════════════════════════════════════════════════════════════════
# EventBridge scheduler: starts the state machine on a recurring schedule.
# ══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "eventbridge_scheduler" {
  name               = "${local.name_prefix}-eventbridge-scheduler"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "eventbridge_scheduler" {
  statement {
    sid       = "StartPipelineExecution"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "eventbridge_scheduler" {
  name   = "${local.name_prefix}-eventbridge-scheduler"
  role   = aws_iam_role.eventbridge_scheduler.id
  policy = data.aws_iam_policy_document.eventbridge_scheduler.json
}
