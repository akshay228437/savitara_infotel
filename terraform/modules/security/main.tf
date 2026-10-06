terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# 1. SECURITY GROUPS (ALB -> EC2 -> RDS ISOLATION CHAIN)
# =============================================================================

# --- ALB Security Group ---
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Internet-facing Application Load Balancer"
  vpc_id      = var.vpc_id

  # Ingress HTTP from internet (redirected to HTTPS)
  ingress {
    description      = "Allow HTTP inbound from anywhere for HTTPS redirect"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Ingress HTTPS from internet
  ingress {
    description      = "Allow HTTPS inbound from anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Egress to EC2 instances on Application Port (8000)
  egress {
    description = "Forward traffic to EC2 Application Instances on port 8000"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # Scoped strictly to VPC
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-sg"
    Environment = var.environment
    Project     = var.project_name
    Tier        = "ALB"
  }
}

# --- EC2 Application Security Group ---
resource "aws_security_group" "ec2_app" {
  name        = "${var.project_name}-${var.environment}-ec2-app-sg"
  description = "Security group for CloudDocs EC2 Auto Scaling instances"
  vpc_id      = var.vpc_id

  # Ingress strictly from ALB Security Group on app_port (8000)
  ingress {
    description     = "Allow inbound HTTP traffic only from ALB on app port"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress for MySQL connection to RDS Security Group
  egress {
    description = "Allow outbound MySQL communication to private RDS tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  # Egress for AWS APIs (S3, Secrets Manager, CloudWatch via NAT or Endpoints) & Package Repositories
  egress {
    description      = "Allow outbound HTTPS for AWS SDK APIs (S3, Secrets Manager) and updates"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "Allow outbound HTTP for OS package updates (yum/dnf)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-ec2-app-sg"
    Environment = var.environment
    Project     = var.project_name
    Tier        = "App-Compute"
  }
}

# --- RDS MySQL Database Security Group ---
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for isolated RDS MySQL Multi-AZ instances"
  vpc_id      = var.vpc_id

  # Ingress strictly from EC2 Application Security Group
  ingress {
    description     = "Allow MySQL traffic strictly from EC2 App Security Group"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_app.id]
  }

  # Isolated RDS does not require outbound internet egress
  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
    Project     = var.project_name
    Tier        = "Database"
  }
}

# =============================================================================
# 2. IAM INSTANCE PROFILE & LEAST-PRIVILEGE ROLES
# =============================================================================

# IAM Role assumed by EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-ec2-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Least-Privilege Policy: S3 Document Bucket Access
resource "aws_iam_policy" "s3_access" {
  name        = "${var.project_name}-${var.environment}-s3-access-policy"
  description = "Least-privilege policy for CloudDocs S3 document uploads and downloads"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListDocumentBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = var.s3_bucket_arn != "" ? [var.s3_bucket_arn] : ["arn:aws:s3:::*"]
      },
      {
        Sid    = "ReadWriteDocuments"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = var.s3_bucket_arn != "" ? ["${var.s3_bucket_arn}/*"] : ["arn:aws:s3:::*/*"]
      }
    ]
  })
}

# Least-Privilege Policy: Secrets Manager Read Access
resource "aws_iam_policy" "secrets_access" {
  name        = "${var.project_name}-${var.environment}-secrets-access-policy"
  description = "Least-privilege policy for CloudDocs to retrieve DB credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetDatabaseSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.db_secret_arn != "" ? [var.db_secret_arn] : ["*"]
      }
    ]
  })
}

# CloudWatch Logs Policy (for centralized application and systemd logs)
resource "aws_iam_policy" "cloudwatch_logs" {
  name        = "${var.project_name}-${var.environment}-cw-logs-policy"
  description = "Policy permitting EC2 instances to push application logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogOperations"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach AWS Systems Manager Core Policy (enables Session Manager without SSH open ports)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach custom least-privilege policies
resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_role_policy_attachment" "secrets_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "cw_logs_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs.arn
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-instance-profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-instance-profile"
    Environment = var.environment
    Project     = var.project_name
  }
}
