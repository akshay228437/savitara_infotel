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

variable "database_subnet_ids" {
  description = "List of isolated private database subnet IDs across 2 AZs"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "Security Group ID for RDS MySQL instance"
  type        = string
}

variable "engine_version" {
  description = "MySQL database engine version"
  type        = string
  default     = "8.0"
}

variable "db_instance_class" {
  description = "RDS database instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage size in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage limit in GiB for RDS autoscaling"
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ high availability deployment"
  type        = bool
  default     = true
}

variable "db_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "clouddocs_db"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  default     = "clouddocs_admin"
}

variable "db_password" {
  description = "Master database password"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "Database listening port"
  type        = number
  default     = 3306
}

variable "kms_key_arn" {
  description = "KMS Key ARN for storage encryption at rest. If empty, default AWS KMS key is used."
  type        = string
  default     = ""
}

variable "backup_retention_period" {
  description = "Days of automated backup retention"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS instance"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of RDS instance"
  type        = bool
  default     = false
}
