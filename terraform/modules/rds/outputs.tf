output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.mysql.id
}

output "db_instance_arn" {
  description = "The RDS instance ARN"
  value       = aws_db_instance.mysql.arn
}

output "db_instance_endpoint" {
  description = "The connection endpoint for the MySQL database (host:port)"
  value       = aws_db_instance.mysql.endpoint
}

output "db_instance_address" {
  description = "The database hostname address"
  value       = aws_db_instance.mysql.address
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.mysql.port
}

output "db_name" {
  description = "The database name"
  value       = aws_db_instance.mysql.db_name
}
