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

variable "vpc_id" {
  description = "VPC ID where the Target Group is registered"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs where the ALB is provisioned across 2 AZs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID of the ALB"
  type        = string
}

variable "app_port" {
  description = "Port on which target instances run CloudDocs application"
  type        = number
  default     = 8000
}

variable "certificate_arn" {
  description = "ARN of the AWS Certificate Manager (ACM) SSL/TLS certificate for HTTPS listener. If provided, Port 80 automatically redirects to Port 443."
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "Security policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "alb_logs_bucket_name" {
  description = "Name of the S3 bucket to store ALB access logs"
  type        = string
  default     = ""
}

variable "enable_alb_logs" {
  description = "Enable ALB access logging to S3"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = false
}
