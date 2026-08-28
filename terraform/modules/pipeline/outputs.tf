output "bucket_names" {
  description = "Map of layer name -> S3 bucket name."
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "glue_database_names" {
  description = "Map of layer name -> Glue Data Catalog database name."
  value       = local.glue_db_names
}

output "lambda_function_names" {
  description = "Map of role -> Lambda function name."
  value = {
    ingestion       = aws_lambda_function.youtube_ingestion.function_name
    json_to_parquet = aws_lambda_function.json_to_parquet.function_name
    data_quality    = aws_lambda_function.data_quality.function_name
  }
}

output "glue_job_names" {
  description = "Map of stage -> Glue job name."
  value = {
    bronze_to_silver = aws_glue_job.bronze_to_silver.name
    silver_to_gold   = aws_glue_job.silver_to_gold.name
  }
}

output "state_machine_arn" {
  description = "ARN of the pipeline's Step Functions state machine."
  value       = aws_sfn_state_machine.pipeline.arn
}

output "sns_topic_arn" {
  description = "ARN of the pipeline's SNS alerts topic."
  value       = aws_sns_topic.alerts.arn
}

output "athena_workgroup" {
  description = "Athena workgroup name used for querying Gold tables."
  value       = aws_athena_workgroup.pipeline.name
}
