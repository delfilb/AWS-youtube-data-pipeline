variable "aws_region" {
  description = "AWS region to create the Terraform state backend resources in."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Short project name used to name the state bucket and lock table."
  type        = string
  default     = "yt-data-pipeline"
}
