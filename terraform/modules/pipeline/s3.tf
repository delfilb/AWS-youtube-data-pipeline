# ── Data lake buckets (Bronze / Silver / Gold) + scripts + Athena results ──────

resource "aws_s3_bucket" "this" {
  for_each = local.bucket_names

  bucket = each.value
  tags   = merge(var.tags, { Layer = each.key })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bronze data is raw and cheap to re-ingest. After 90 days, transition old raw
# JSON to Glacier Flexible Retrieval to cut storage cost while keeping it
# recoverable for backfills. Silver/Gold are curated and kept in Standard.
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.this["bronze"].id

  rule {
    id     = "archive-old-raw-data"
    status = "Enabled"

    filter {
      prefix = "youtube/"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Athena query result objects are transient scratch output.
resource "aws_s3_bucket_lifecycle_configuration" "athena" {
  bucket = aws_s3_bucket.this["athena"].id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 14
    }
  }
}

# ── Glue ETL scripts ─────────────────────────────────────────────────────────

resource "aws_s3_object" "bronze_to_silver_script" {
  bucket = aws_s3_bucket.this["scripts"].id
  key    = "glue_jobs/bronze_to_silver_statistics.py"
  source = local.glue_script_paths.bronze_to_silver
  etag   = filemd5(local.glue_script_paths.bronze_to_silver)
}

resource "aws_s3_object" "silver_to_gold_script" {
  bucket = aws_s3_bucket.this["scripts"].id
  key    = "glue_jobs/silver_to_gold_analytics.py"
  source = local.glue_script_paths.silver_to_gold
  etag   = filemd5(local.glue_script_paths.silver_to_gold)
}

# The reference-data transform is invoked in-band by the Step Functions
# "TransformReferenceData" step (which passes the regions ingested that run), not
# by an async S3 notification. A bucket notification here would double-process
# every file — once from the event, once from the pipeline — with two concurrent
# overwrite_partitions writes racing on the same Glue partitions. If you ever need
# an out-of-band path for manual drops, add a notification to a *different*
# prefix and point it at a separate handler.
