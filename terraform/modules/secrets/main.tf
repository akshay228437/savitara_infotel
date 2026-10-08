terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
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
    password = var.db_password   # <-- Directly use the input variable
    dbname   = var.db_name
  })
}