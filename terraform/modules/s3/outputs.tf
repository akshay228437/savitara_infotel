output "documents_bucket_name" {
  description = "Name of the secure S3 document vault bucket"
  value       = aws_s3_bucket.documents.id
}

output "documents_bucket_arn" {
  description = "ARN of the secure S3 document vault bucket"
  value       = aws_s3_bucket.documents.arn
}

output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket designated for ALB access logging"
  value       = aws_s3_bucket.alb_logs.id
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket designated for ALB access logging"
  value       = aws_s3_bucket.alb_logs.arn
}
