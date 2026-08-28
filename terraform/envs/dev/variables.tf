variable "aws_region" {
  description = "AWS region to deploy the pipeline into."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short project name used as a prefix for all resource names."
  type        = string
  default     = "yt-data-pipeline"
}

variable "youtube_api_key" {
  description = "YouTube Data API v3 key."
  type        = string
  sensitive   = true
}

variable "youtube_regions" {
  description = "Region codes to ingest trending data for."
  type        = list(string)
  default     = ["US", "GB", "CA", "DE", "FR", "IN", "JP", "KR", "MX", "RU"]
}

variable "alert_email" {
  description = "Email address subscribed to pipeline SNS alerts. Empty to skip."
  type        = string
  default     = ""
}

variable "pandas_layer_arn" {
  description = "ARN of the AWS SDK for pandas Lambda layer matching var.aws_region / lambda_runtime."
  type        = string
}

variable "pipeline_schedule_expression" {
  description = "EventBridge schedule expression for the pipeline."
  type        = string
  default     = "rate(6 hours)"
}

variable "enable_schedule" {
  description = "Whether the scheduled trigger is enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Project = "yt-data-pipeline"
  }
}
