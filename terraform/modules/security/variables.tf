variable "project_name" {
  description = "The project name prefix for resource tagging and identification"
  type        = string
  default     = "clouddocs"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_id" {
  description = "VPC ID where security groups will be provisioned"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for internal traffic boundaries"
  type        = string
}

variable "app_port" {
  description = "Application listening port on EC2 instances"
  type        = number
  default     = 8000
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 documents bucket for IAM policy least-privilege scoping"
  type        = string
  default     = ""
}

variable "db_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret for RDS credentials"
  type        = string
  default     = ""
}
