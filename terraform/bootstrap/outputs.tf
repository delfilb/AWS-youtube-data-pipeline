output "state_bucket_name" {
  description = "S3 bucket to use as the Terraform backend 'bucket' for envs/*."
  value       = aws_s3_bucket.tfstate.id
}

output "lock_table_name" {
  description = "DynamoDB table to use as the Terraform backend 'dynamodb_table' for envs/*."
  value       = aws_dynamodb_table.tfstate_lock.name
}
