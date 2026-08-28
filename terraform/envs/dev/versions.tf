terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Partial backend configuration: bucket/dynamodb_table come from
  # terraform/bootstrap's outputs and are supplied at `terraform init` time
  # via -backend-config=backend.hcl (see backend.hcl.example).
  backend "s3" {
    key     = "yt-data-pipeline/dev/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
