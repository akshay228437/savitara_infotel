# =============================================================================
# GENERAL PROJECT VARIABLES
# =============================================================================
variable "project_name" {
  description = "The prefix to apply to all resources"
  type        = string
  default     = "clouddocs"
}

variable "environment" {
  description = "Target deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS Region to deploy infrastructure into"
  type        = string
  default     = "us-east-1"
}

# =============================================================================
# NETWORKING VARIABLES (VPC & SUBNETS)
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the custom CloudDocs VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two distinct Availability Zones for Multi-AZ high availability"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for Public Subnets (ALB & NAT Gateways)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for Private App Subnets (EC2 ASG)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for Isolated Private DB Subnets (RDS MySQL)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "single_nat_gateway" {
  description = "Deploy a single NAT Gateway across AZs to minimize lab costs (false for strict HA multi-NAT)"
  type        = bool
  default     = true
}

# =============================================================================
# DATABASE (RDS MYSQL) & SECRETS MANAGER VARIABLES
# =============================================================================
variable "db_name" {
  description = "Name of the MySQL schema to create"
  type        = string
  default     = "clouddocs_db"
}

variable "db_username" {
  description = "Master username for RDS MySQL database"
  type        = string
  default     = "clouddocs_admin"
}

variable "db_instance_class" {
  description = "Instance class for RDS MySQL"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage allocated in GiB for RDS MySQL"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment for RDS MySQL high availability"
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS instance"
  type        = bool
  default     = true
}

# =============================================================================
# COMPUTE & BALANCING (ALB & ASG) VARIABLES
# =============================================================================
variable "app_port" {
  description = "Port on which the FastAPI CloudDocs application listens"
  type        = number
  default     = 8000
}

variable "instance_type" {
  description = "EC2 instance type for Auto Scaling Group nodes"
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the ASG (Multi-AZ across 2 subnets)"
  type        = number
  default     = 2
}

variable "certificate_arn" {
  description = "ACM SSL/TLS certificate ARN for the ALB HTTPS listener. If specified, HTTP traffic redirects to HTTPS."
  type        = string
  default     = ""
}

variable "enable_alb_logs" {
  description = "Enable ALB access logs written to S3 logging bucket"
  type        = bool
  default     = true
}

variable "repo_url" {
  description = "Optional Git repository URL cloned by EC2 bootstrap user-data"
  type        = string
  default     = ""
}

variable "force_destroy_s3" {
  description = "Allow destruction of non-empty S3 buckets during terraform destroy"
  type        = bool
  default     = false
}
