output "bucket_names" {
  value = module.pipeline.bucket_names
}

output "glue_database_names" {
  value = module.pipeline.glue_database_names
}

output "lambda_function_names" {
  value = module.pipeline.lambda_function_names
}

output "glue_job_names" {
  value = module.pipeline.glue_job_names
}

output "state_machine_arn" {
  value = module.pipeline.state_machine_arn
}

output "sns_topic_arn" {
  value = module.pipeline.sns_topic_arn
}

output "athena_workgroup" {
  value = module.pipeline.athena_workgroup
}
