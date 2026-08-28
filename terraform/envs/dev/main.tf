module "pipeline" {
  source = "../../modules/pipeline"

  project_name = var.project_name
  environment  = "dev"
  aws_region   = var.aws_region
  tags         = var.tags

  youtube_api_key  = var.youtube_api_key
  youtube_regions  = var.youtube_regions
  alert_email      = var.alert_email
  pandas_layer_arn = var.pandas_layer_arn

  pipeline_schedule_expression = var.pipeline_schedule_expression
  enable_schedule              = var.enable_schedule
}
