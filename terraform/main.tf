# =============================================================================
# CloudDocs Enterprise Architecture - Root Terraform Composition
# =============================================================================

# Cryptographically secure random master password for RDS MySQL instance
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# 1. AWS NETWORKING: Custom VPC across 2 Availability Zones
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name              = var.project_name
  environment               = var.environment
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs   = var.private_app_subnet_cidrs
  private_db_subnet_cidrs    = var.private_db_subnet_cidrs
  single_nat_gateway        = var.single_nat_gateway
}

# -----------------------------------------------------------------------------
# 2. STORAGE: Private S3 Document Vault & ALB Logging Buckets
# -----------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  project_name  = var.project_name
  environment   = var.environment
  force_destroy = var.force_destroy_s3
}

# -----------------------------------------------------------------------------
# 3. DATABASE: Isolated RDS MySQL Multi-AZ Instance
# -----------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  project_name          = var.project_name
  environment           = var.environment
  database_subnet_ids   = module.vpc.private_db_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = random_password.db_password.result
  db_instance_class     = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.rds_multi_az
  skip_final_snapshot   = var.rds_skip_final_snapshot
}

# -----------------------------------------------------------------------------
# 4. SECRETS MANAGEMENT: AWS Secrets Manager for DB Credentials
# -----------------------------------------------------------------------------
module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  db_username  = var.db_username
  db_password  = random_password.db_password.result
  db_name      = var.db_name
  db_host      = module.rds.db_instance_address
  db_port      = module.rds.db_instance_port
}

# -----------------------------------------------------------------------------
# 5. SECURITY & IAM: Security Groups (ALB -> EC2 -> RDS) & EC2 Instance Profile
# -----------------------------------------------------------------------------
module "security" {
  source = "./modules/security"

  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block
  app_port       = var.app_port
  s3_bucket_arn  = module.s3.documents_bucket_arn
  db_secret_arn  = module.secrets.secret_arn
}

# -----------------------------------------------------------------------------
# 6. APPLICATION LOAD BALANCER (ALB) with SSL/TLS Listener & HTTP->HTTPS Redirect
# -----------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  app_port              = var.app_port
  certificate_arn       = var.certificate_arn
  alb_logs_bucket_name  = module.s3.alb_logs_bucket_name
  enable_alb_logs       = var.enable_alb_logs
}

# -----------------------------------------------------------------------------
# 7. COMPUTE: Auto Scaling Group & Launch Template with Bootstrap User-Data
# -----------------------------------------------------------------------------
module "asg" {
  source = "./modules/asg"

  project_name            = var.project_name
  environment             = var.environment
  aws_region              = var.aws_region
  private_app_subnet_ids  = module.vpc.private_app_subnet_ids
  target_group_arn        = module.alb.target_group_arn
  ec2_security_group_id   = module.security.ec2_security_group_id
  instance_profile_arn    = module.security.ec2_instance_profile_arn
  document_bucket_name    = module.s3.documents_bucket_name
  db_secret_arn           = module.secrets.secret_arn
  repo_url                = var.repo_url
  instance_type           = var.instance_type
  min_size                = var.asg_min_size
  max_size                = var.asg_max_size
  desired_capacity        = var.asg_desired_capacity
}
