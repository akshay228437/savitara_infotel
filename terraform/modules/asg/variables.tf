variable "project_name" {
  description = "Project name prefix for resource naming and tagging"
  type        = string
  default     = "clouddocs"
}

variable "environment" {
  description = "Environment identifier (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "private_app_subnet_ids" {
  description = "List of private application subnet IDs where EC2 instances will be launched"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ARN of the ALB Target Group to attach the ASG to"
  type        = string
}

variable "ec2_security_group_id" {
  description = "Security Group ID for EC2 instances"
  type        = string
}

variable "instance_profile_arn" {
  description = "ARN of the IAM Instance Profile attached to the EC2 instances"
  type        = string
}

variable "document_bucket_name" {
  description = "Name of the S3 bucket used for document storage"
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing RDS database credentials"
  type        = string
}

variable "repo_url" {
  description = "Git repository URL containing the CloudDocs application code (optional, fallback used if empty)"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "Optional specific AMI ID. If empty, the latest Amazon Linux 2023 AMI is resolved automatically."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for application nodes"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GiB"
  type        = number
  default     = 20
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of instances in the ASG"
  type        = number
  default     = 2
}
