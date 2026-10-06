# =============================================================================
# CloudDocs Infrastructure Outputs
# =============================================================================

output "alb_dns_name" {
  description = "The public DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "application_url" {
  description = "Application entry point URL (HTTPS if ACM certificate configured, otherwise HTTP)"
  value       = var.certificate_arn != "" ? "https://${module.alb.alb_dns_name}" : "http://${module.alb.alb_dns_name}"
}

output "vpc_id" {
  description = "The ID of the custom CloudDocs VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "IDs of the public subnets across 2 AZs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnets" {
  description = "IDs of the private application compute subnets across 2 AZs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnets" {
  description = "IDs of the isolated private database subnets across 2 AZs"
  value       = module.vpc.private_db_subnet_ids
}

output "document_bucket_name" {
  description = "Name of the encrypted S3 document vault bucket"
  value       = module.s3.documents_bucket_name
}

output "document_bucket_arn" {
  description = "ARN of the encrypted S3 document vault bucket"
  value       = module.s3.documents_bucket_arn
}

output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket storing ALB access logs"
  value       = module.s3.alb_logs_bucket_name
}

output "db_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret storing RDS credentials"
  value       = module.secrets.secret_arn
}

output "db_secret_name" {
  description = "Name of the AWS Secrets Manager secret"
  value       = module.secrets.secret_name
}

output "rds_endpoint" {
  description = "Connection endpoint of the RDS MySQL instance (address:port)"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "Host address of the RDS MySQL database"
  value       = module.rds.db_instance_address
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group running CloudDocs instances"
  value       = module.asg.autoscaling_group_name
}

output "target_group_arn" {
  description = "ARN of the ALB Target Group"
  value       = module.alb.target_group_arn
}
