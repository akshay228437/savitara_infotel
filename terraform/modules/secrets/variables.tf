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

variable "db_username" {
  description = "Master database username for MySQL"
  type        = string
  default     = "clouddocs_admin"
}

variable "db_password" {
  description = "Optional pre-generated master database password. If empty, a random password is generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "db_name" {
  description = "Initial database name for CloudDocs"
  type        = string
  default     = "clouddocs_db"
}

variable "db_host" {
  description = "Database host address (populated once RDS instance endpoint is known)"
  type        = string
  default     = "localhost"
}

variable "db_port" {
  description = "Database listening port"
  type        = number
  default     = 3306
}

variable "recovery_window_in_days" {
  description = "Number of days AWS Secrets Manager waits before deleting recovery secret (0 for immediate deletion in labs)"
  type        = number
  default     = 0
}
