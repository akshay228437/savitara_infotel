output "alb_security_group_id" {
  description = "Security Group ID of the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "Security Group ID of the EC2 Auto Scaling instances"
  value       = aws_security_group.ec2_app.id
}

output "rds_security_group_id" {
  description = "Security Group ID of the isolated RDS MySQL cluster"
  value       = aws_security_group.rds.id
}

output "ec2_iam_role_name" {
  description = "IAM Role Name assumed by EC2 instances"
  value       = aws_iam_role.ec2_role.name
}

output "ec2_iam_role_arn" {
  description = "IAM Role ARN assumed by EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

output "ec2_instance_profile_name" {
  description = "IAM Instance Profile Name for EC2 Launch Template"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_instance_profile_arn" {
  description = "IAM Instance Profile ARN for EC2 Launch Template"
  value       = aws_iam_instance_profile.ec2_profile.arn
}
