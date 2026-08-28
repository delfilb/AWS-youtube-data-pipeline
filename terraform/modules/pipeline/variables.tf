variable "project_name" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "yt-data-pipeline"
}

variable "environment" {
  description = "Deployment environment name (dev, staging, prod, ...)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region resources are deployed into."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource that supports them."
  type        = map(string)
  default     = {}
}

# ── YouTube ingestion ─────────────────────────────────────────────────────────

variable "youtube_api_key" {
  description = "YouTube Data API v3 key used by the ingestion Lambda."
  type        = string
  sensitive   = true
}

variable "youtube_regions" {
  description = "Comma will be joined from this list: region codes to ingest trending data for."
  type        = list(string)
  default     = ["US", "GB", "CA", "DE", "FR", "IN", "JP", "KR", "MX", "RU"]
}

# ── Alerting ───────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email address subscribed to the pipeline's SNS alert topic. Leave empty to skip creating a subscription."
  type        = string
  default     = ""
}

# ── Scheduling ─────────────────────────────────────────────────────────────────

variable "pipeline_schedule_expression" {
  description = "EventBridge schedule expression that triggers the Step Functions state machine."
  type        = string
  default     = "rate(6 hours)"
}

variable "enable_schedule" {
  description = "Whether the EventBridge schedule rule is enabled on creation."
  type        = bool
  default     = true
}

# ── Lambda ─────────────────────────────────────────────────────────────────────

variable "lambda_runtime" {
  description = "Python runtime shared by all three Lambda functions."
  type        = string
  default     = "python3.11"
}

variable "pandas_layer_arn" {
  description = <<-EOT
    ARN of the AWS-managed "AWS SDK for pandas" Lambda layer (provides pandas +
    awswrangler) for the json-to-parquet and data-quality functions. Must match
    var.lambda_runtime and var.aws_region. Look up the current version at:
    https://aws-sdk-pandas.readthedocs.io/en/stable/layers.html
    Example for us-east-2 / python3.11:
    arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python311:14
  EOT
  type        = string
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for the ingestion and transform Lambdas."
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Memory (MB) for the ingestion and transform Lambdas."
  type        = number
  default     = 512
}

variable "lambda_ephemeral_storage_mb" {
  description = "Ephemeral storage (/tmp, MB) for the ingestion and transform Lambdas."
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for Lambda and Glue job log groups."
  type        = number
  default     = 30
}

# ── Data quality thresholds ────────────────────────────────────────────────────

variable "dq_min_row_count" {
  description = "Minimum row count for the Silver layer DQ gate."
  type        = number
  default     = 10
}

variable "dq_max_null_percent" {
  description = "Maximum allowed null percentage on critical columns for the Silver layer DQ gate."
  type        = number
  default     = 5.0
}

variable "dq_freshness_hours" {
  description = "Maximum age (hours) of the newest record before the Silver DQ freshness check fails. Applies to any table without a specific override."
  type        = number
  default     = 48
}

variable "dq_reference_freshness_hours" {
  description = "Freshness window (hours) for clean_reference_data specifically. Category reference data is near-static, so it gets a much wider window than the trending statistics."
  type        = number
  default     = 720
}

# ── Glue ───────────────────────────────────────────────────────────────────────

variable "glue_version" {
  description = "Glue version for the ETL jobs."
  type        = string
  default     = "4.0"
}

variable "glue_worker_type" {
  description = "Worker type for the Glue ETL jobs."
  type        = string
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Number of workers for the Glue ETL jobs."
  type        = number
  default     = 2
}

variable "glue_crawler_schedule" {
  description = "Cron schedule (Glue crawler syntax) that keeps the Bronze raw_statistics table and its partitions up to date. Set to null to disable scheduling (on-demand only)."
  type        = string
  default     = "cron(15 * * * ? *)"
}
