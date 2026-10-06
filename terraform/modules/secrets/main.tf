terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

# Auto-generate a secure random master password if not supplied externally
resource "random_password" "generated_db_password" {
  count            = var.db_password == "" ? 1 : 0
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  effective_password = var.db_password != "" ? var.db_password : random_password.generated_db_password[0].result
}

# AWS Secrets Manager Secret container
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/rds-mysql-credentials"
  description             = "Master database credentials and connection parameters for CloudDocs RDS MySQL"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-secret"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Secret Version storing the credentials payload in JSON format
resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "mysql"
    host     = var.db_host
    port     = var.db_port
    username = var.db_username
    password = locals.effective_password
    dbname   = var.db_name
  })
}
