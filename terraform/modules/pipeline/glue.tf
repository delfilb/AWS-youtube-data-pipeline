# ── Glue Data Catalog databases ────────────────────────────────────────────────

resource "aws_glue_catalog_database" "bronze" {
  name = local.glue_db_names.bronze
}

resource "aws_glue_catalog_database" "silver" {
  name = local.glue_db_names.silver
}

resource "aws_glue_catalog_database" "gold" {
  name = local.glue_db_names.gold
}

# ── Bronze crawler ──────────────────────────────────────────────────────────────
# The ingestion Lambda writes raw JSON to
#   s3://<bronze>/youtube/raw_statistics/region=XX/date=YYYY-MM-DD/hour=HH/
#   s3://<bronze>/youtube/raw_statistics_reference_data/region=XX/date=YYYY-MM-DD/
# The crawler discovers the schema + Hive partitions for both prefixes and
# registers/updates the "raw_statistics" table (read by the bronze_to_silver
# Glue job) plus a raw reference-data table for ad-hoc Athena queries.
# Silver/Gold tables need no crawler: the Glue jobs and the json-to-parquet
# Lambda register/update those tables themselves (enableUpdateCatalog / awswrangler).

resource "aws_glue_crawler" "raw_statistics" {
  name          = "${local.name_prefix}-raw-statistics-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.bronze.name
  schedule      = var.glue_crawler_schedule
  tags          = var.tags

  s3_target {
    path = "s3://${aws_s3_bucket.this["bronze"].id}/youtube/raw_statistics/"
  }

  s3_target {
    path = "s3://${aws_s3_bucket.this["bronze"].id}/youtube/raw_statistics_reference_data/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# ── Glue ETL jobs ────────────────────────────────────────────────────────────────

resource "aws_glue_job" "bronze_to_silver" {
  name              = "${local.name_prefix}-bronze-to-silver"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  timeout           = 60
  tags              = var.tags

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.this["scripts"].id}/${aws_s3_object.bronze_to_silver_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--bronze_database"                  = aws_glue_catalog_database.bronze.name
    "--bronze_table"                     = "raw_statistics"
    "--silver_bucket"                    = aws_s3_bucket.this["silver"].id
    "--silver_database"                  = aws_glue_catalog_database.silver.name
    "--silver_table"                     = "clean_statistics"
  }
}

resource "aws_glue_job" "silver_to_gold" {
  name              = "${local.name_prefix}-silver-to-gold"
  role_arn          = aws_iam_role.glue_job.arn
  glue_version      = var.glue_version
  worker_type       = var.glue_worker_type
  number_of_workers = var.glue_number_of_workers
  timeout           = 60
  tags              = var.tags

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.this["scripts"].id}/${aws_s3_object.silver_to_gold_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--silver_database"                  = aws_glue_catalog_database.silver.name
    "--gold_bucket"                      = aws_s3_bucket.this["gold"].id
    "--gold_database"                    = aws_glue_catalog_database.gold.name
  }
}
