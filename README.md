# CloudDocs — Secure Corporate Document Portal

[![Terraform CI/CD](https://github.com/organization/clouddocs/actions/workflows/terraform-ci-cd.yml/badge.svg)](https://github.com/organization/clouddocs/actions/workflows/terraform-ci-cd.yml)
[![Application CI](https://github.com/organization/clouddocs/actions/workflows/app-ci.yml/badge.svg)](https://github.com/organization/clouddocs/actions/workflows/app-ci.yml)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Architecture-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110.0-009688?logo=fastapi)](https://fastapi.tiangolo.com/)
[![TailwindCSS](https://img.shields.io/badge/TailwindCSS-v3.4-38B2AC?logo=tailwind-css)](https://tailwindcss.com/)

**CloudDocs** is an end-to-end, production-grade DevOps solution providing an enterprise-grade document repository. Built with security-first architecture principles on **Amazon Web Services (AWS)** using **Terraform Infrastructure as Code (IaC)**, automated through **GitHub Actions CI/CD**, and backed by a modern **Python FastAPI + Tailwind CSS** application stack.

---

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Structural Data Flow Diagram](#structural-data-flow-diagram)
3. [End-to-End Request Lifecycles](#end-to-end-request-lifecycles)
4. [Security & Isolation Matrix](#security--isolation-matrix)
5. [Repository Structure](#repository-structure)
6. [Prerequisites](#prerequisites)
7. [Deployment Guide (Terraform)](#deployment-guide-terraform)
8. [Secrets Management & Rotation](#secrets-management--rotation)
9. [HTTPS & ACM Verification](#https--acm-verification)
10. [Local Development & Mock Testing](#local-development--mock-testing)
11. [CI/CD Pipeline Details](#cicd-pipeline-details)

---

## Architecture Overview

The infrastructure enforces strict network isolation and least-privilege access across multiple tiers:

- **Custom AWS VPC (`10.0.0.0/16`)**: Partitioned across **2 Availability Zones** (`us-east-1a`, `us-east-1b`) into six dedicated subnets:
  - **Public Subnets (`10.0.1.0/24`, `10.0.2.0/24`)**: Host the Internet-facing Application Load Balancer (ALB) and NAT Gateway.
  - **Private Compute Subnets (`10.0.11.0/24`, `10.0.12.0/24`)**: Host the EC2 Auto Scaling Group (ASG) instances. No direct inbound access from the Internet.
  - **Private Isolated DB Subnets (`10.0.21.0/24`, `10.0.22.0/24`)**: Host the Multi-AZ RDS MySQL database. Completely isolated with **zero outbound internet routing**.
- **Application Load Balancer (ALB)**:
  - Listens on Port 80 (HTTP) and **automatically redirects 301 to Port 443 (HTTPS)**.
  - Terminates TLS using an AWS Certificate Manager (ACM) certificate.
  - Routinely evaluates the application target group on `/healthz`.
  - Publishes full access audit logs to a dedicated S3 logging bucket.
- **Compute (Auto Scaling Group & Launch Template)**:
  - Deploys EC2 instances running Amazon Linux 2023 across both private compute subnets.
  - Custom cloud-init bootstrap script (`user_data.sh.tpl`) provisions Python 3.11, clones application code, installs dependencies, and manages the app via a sandboxed `systemd` service (`clouddocs.service`).
  - Enforces **IMDSv2** (`http_tokens = "required"`) and encrypts root EBS volumes (`gp3`).
  - Target-tracking autoscaling policy scales nodes automatically based on CPU utilization (70%).
- **Database (RDS MySQL Multi-AZ)**:
  - High-availability deployment with automatic synchronous failover between AZs.
  - Encrypted at rest via AWS KMS.
- **Secrets Management (AWS Secrets Manager)**:
  - Generates and stores master database credentials securely in JSON format.
  - Eliminates hardcoded passwords from version control and Terraform configurations.
- **Payload Storage (Amazon S3)**:
  - Private S3 Bucket with `block_public_access` (100% blocked), Server-Side Encryption (SSE-KMS / AES-256), and bucket policies denying non-TLS traffic.
  - Generates time-limited (15-minute) **Presigned S3 URLs** for secure file downloads.

---

## Structural Data Flow Diagram

```
                                 [ INTERNET CLIENT ]
                                          |
                        HTTPS:443 (HTTP:80 -> 301 Redirect)
                                          |
                                 +-----------------+
                                 | Internet Gateway|
                                 +-----------------+
                                          |
       ========================= AWS VPC (10.0.0.0/16) =========================
      ||                                                                       ||
      ||   PUBLIC SUBNETS (10.0.1.0/24, 10.0.2.0/24 across 2 AZs)              ||
      ||   +---------------------------------------------------------------+   ||
      ||   |            Application Load Balancer (ALB)                    |   ||
      ||   |  - ACM SSL/TLS Listener (443) -> Target Group (Port 8000)     |   ||
      ||   |  - HTTP (80) -> Redirect to HTTPS 443                         |   ||
      ||   +---------------------------------------------------------------+   ||
      ||            |                                         |                ||
      ||            | Port 8000 Forward                       | Access Logs    ||
      ||            v                                         v                ||
      ||   PRIVATE COMPUTE SUBNETS (10.0.11.0/24, 10.0.12.0/24 across 2 AZs)   ||
      ||   +---------------------------------------------------------------+   ||
      ||   |            Auto Scaling Group (EC2 Instances)                 |   ||
      ||   |   +-----------------------+     +-----------------------+     |   ||
      ||   |   | EC2 Node (AZ-a)       |     | EC2 Node (AZ-b)       |     |   ||
      ||   |   | - FastAPI (Uvicorn)   |     | - FastAPI (Uvicorn)   |     |   ||
      ||   |   | - Boto3 AWS SDK       |     | - Boto3 AWS SDK       |     |   ||
      ||   |   | - PyMySQL Client      |     | - PyMySQL Client      |     |   ||
      ||   |   +-----------------------+     +-----------------------+     |   ||
      ||   |           | IAM Instance Profile: Scoped Least-Privilege Role |   ||
      ||   +-----------+-----------------------------+---------------------+   ||
      ||               |                             |                         ||
      ||     [SQL Port 3306]                         |                         ||
      ||               v                             |                         ||
      ||   ISOLATED DB SUBNETS (10.0.21.0/24, 10.0.22.0/24 across 2 AZs)       ||
      ||   +---------------------------------------------------------------+   ||
      ||   |              RDS MySQL Multi-AZ Database Cluster              |   ||
      ||   |   [Primary Writer (AZ-a)] <==== Sync Rep ====> [Standby (AZ-b)]   ||
      ||   |   (Encrypted with KMS gp3, strictly NO internet gateway route)|   ||
      ||   +---------------------------------------------------------------+   ||
      ||                                                                       ||
       =========================================================================
                          |                                   |
             [AWS SDK: GetSecretValue]            [AWS SDK: PutObject/Presigned]
                          v                                   v
             +--------------------------+       +------------------------------+
             |   AWS Secrets Manager    |       |   Encrypted S3 Buckets       |
             | - RDS credentials JSON   |       | - Payload Vault (SSE-KMS)    |
             | - Auto-generated pass    |       | - ALB Logs (SSL Enforced)    |
             +--------------------------+       +------------------------------+
```

---

## End-to-End Request Lifecycles

### 1. Document Upload Lifecycle (`POST /upload`)
1. User selects a document on the CloudDocs dashboard and clicks **Upload Payload**.
2. Request travels via HTTPS to the ALB and forwards to an EC2 instance on port 8000.
3. The FastAPI app processes the `multipart/form-data` stream.
4. Using `boto3`, the app streams binary bytes directly into the private S3 document bucket with `ServerSideEncryption="AES256"` (or AWS KMS).
5. Upon successful S3 upload, metadata (`filename`, `s3_key`, `file_size`, `uploader`, `category`, `timestamp`) is written into the RDS MySQL database using `pymysql`.
6. API returns HTTP 201 with the created metadata payload, triggering an interactive dashboard refresh.

### 2. Document Download Lifecycle (`GET /download/{id}`)
1. User clicks the **Download** button for a vaulted file.
2. Request hits `GET /download/{id}` on the backend.
3. Backend looks up the document row in RDS MySQL to obtain the corresponding `s3_key` and filename.
4. Using `boto3.client('s3').generate_presigned_url(...)`, the backend creates an authenticated, cryptographically signed S3 GET URL with a **15-minute expiration window**.
5. Server sends an **HTTP 307 Temporary Redirect** pointing directly to the presigned S3 URL.
6. The client browser downloads the encrypted payload directly from S3 without proxying large files through EC2, preserving server bandwidth.

### 3. High-Availability Health Check (`GET /healthz`)
1. The ALB target group polls `/healthz` on each EC2 instance every 30 seconds.
2. The endpoint verifies active connectivity to both RDS MySQL and the S3 storage bucket.
3. If both subsystems are functioning normally, it returns `HTTP 200 OK` with JSON diagnostics.
4. Instances failing 3 consecutive health checks are automatically deregistered by the ALB and replaced by the Auto Scaling Group.

---

## Security & Isolation Matrix

| Component | Inbound Rules | Outbound Rules | IAM Privileges |
| :--- | :--- | :--- | :--- |
| **ALB Security Group** | Ports 80 & 443 from `0.0.0.0/0` | Port 8000 to `ec2_app_sg` only | N/A |
| **EC2 App Security Group** | Port 8000 strictly from `alb_sg` | Port 3306 to `rds_sg`, 443 to AWS APIs via NAT | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `secretsmanager:GetSecretValue`, CloudWatch Logs, SSM Core |
| **RDS Security Group** | Port 3306 strictly from `ec2_app_sg` | None (Isolated) | N/A |
| **S3 Document Bucket** | Block Public Access: 100% On | TLS Enforced (`aws:SecureTransport: true`) | Scoped to EC2 IAM Role |
| **AWS Secrets Manager** | Encrypted with AWS KMS | Scoped access | Read-only for EC2 IAM Role |

---

## Repository Structure

```
savitara_infotel/
├── .github/
│   └── workflows/
│       ├── terraform-ci-cd.yml      # Automated lint, plan, and apply workflow
│       └── app-ci.yml               # Automated Python test & Docker verification
├── app/
│   ├── templates/
│   │   └── index.html               # Single-file responsive Tailwind CSS dashboard
│   ├── config.py                    # Environment settings & mock mode detection
│   ├── db.py                        # PyMySQL + AWS Secrets Manager + SQLite fallback
│   ├── storage.py                   # Boto3 S3 SSE integration + presigned URLs
│   ├── schemas.py                   # Pydantic validation models
│   ├── main.py                      # FastAPI routes (/, /upload, /download, /healthz)
│   ├── requirements.txt             # Application dependencies
│   ├── Dockerfile                   # Multi-stage non-root container image
│   └── test_app.py                  # Integration & unit test suite
├── terraform/
│   ├── modules/
│   │   ├── vpc/                     # Custom VPC, 6 Subnets across 2 AZs, NAT, IGW
│   │   ├── security/                # ALB -> EC2 -> RDS SG chain & IAM policies
│   │   ├── s3/                      # Document vault & ALB logging buckets
│   │   ├── secrets/                 # AWS Secrets Manager DB credentials & random pass
│   │   ├── rds/                     # Multi-AZ RDS MySQL with KMS encryption
│   │   ├── alb/                     # ALB, ACM HTTPS listener, 80->443 redirect, TG
│   │   └── asg/                     # Launch Template (IMDSv2, gp3) & Auto Scaling Group
│   ├── main.tf                      # Root composition wiring all modules
│   ├── variables.tf                 # Variable parameterization and defaults
│   ├── outputs.tf                   # ALB DNS name, S3 buckets, RDS endpoints
│   ├── versions.tf                  # Required providers and backend declaration
│   └── terraform.tfvars.example     # Ready-to-use sample configuration
├── scripts/
│   ├── local_run.py                 # Convenience local runner in mock mode
│   └── init_db.sql                  # MySQL schema definition reference
├── .env.example                     # Environment variables template
├── .gitignore                       # Clean Git tracking policies
└── README.md                        # Complete documentation & deployment guide
```

---

## Prerequisites

Before deploying the CloudDocs infrastructure, ensure you have:

1. **AWS CLI** (v2) configured with appropriate IAM administrator credentials:
   ```bash
   aws configure
   aws sts get-caller-identity
   ```
2. **Terraform** (>= 1.5.0):
   ```bash
   terraform -version
   ```
3. **Python 3.11+** (for local development or testing):
   ```bash
   python --version
   ```
4. *(Optional)* **AWS ACM Certificate ARN**: If you have a custom domain managed in Route 53 or external DNS, request/import an SSL certificate in AWS Certificate Manager in the target region (`us-east-1`).

---

## Deployment Guide (Terraform)

### Step 1: Clone Repository & Configure Variables
```bash
git clone https://github.com/organization/clouddocs.git
cd clouddocs/terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to suit your requirements:
```hcl
project_name        = "clouddocs"
environment         = "prod"
aws_region          = "us-east-1"
single_nat_gateway  = true       # Set true for lab cost savings, false for full HA NAT

# If you have an ACM SSL certificate:
certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/YOUR-CERT-ID"
```

### Step 2: Initialize Terraform Modules & Providers
```bash
terraform init
```

### Step 3: Validate Syntax & Generate Execution Plan
```bash
terraform fmt -check
terraform validate
terraform plan -out=tfplan
```

### Step 4: Provision Cloud Infrastructure
```bash
terraform apply tfplan
```

Upon completion, Terraform will output your infrastructure endpoints:
```
Outputs:
alb_dns_name          = "clouddocs-prod-alb-123456789.us-east-1.elb.amazonaws.com"
application_url       = "https://clouddocs-prod-alb-123456789.us-east-1.elb.amazonaws.com"
document_bucket_name  = "clouddocs-prod-documents-a1b2c3"
db_secret_name        = "clouddocs/prod/rds-mysql-credentials"
rds_endpoint          = "clouddocs-prod-mysql.xxxx.us-east-1.rds.amazonaws.com:3306"
```

---

## Secrets Management & Rotation

CloudDocs utilizes **AWS Secrets Manager** to manage database credentials with zero hardcoded credentials:

1. **Generation**: During Terraform execution, `random_password.db_password` generates a 20-character cryptographically secure password with special characters.
2. **Storage**: The password and connection parameters are committed to `aws_secretsmanager_secret.db_credentials` with the schema:
   ```json
   {
     "engine": "mysql",
     "host": "<rds-hostname>",
     "port": 3306,
     "username": "clouddocs_admin",
     "password": "<auto-generated-password>",
     "dbname": "clouddocs_db"
   }
   ```
3. **Retrieval**: At application boot on EC2, the instance queries Secrets Manager using its attached IAM role:
   ```python
   client = boto3.client("secretsmanager", region_name=settings.AWS_REGION)
   response = client.get_secret_value(SecretId=settings.SECRET_ARN_DB)
   credentials = json.loads(response["SecretString"])
   ```
4. **Credential Rotation**: To rotate credentials:
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id "clouddocs/prod/rds-mysql-credentials" \
     --rotation-lambda-arn "<rotation-lambda-arn>"
   ```

---

## HTTPS & ACM Verification

### Automated Redirection (Port 80 -> Port 443)
The ALB listener is configured with an automated HTTP 301 redirection rule. When you query the HTTP endpoint:
```bash
curl -I http://<alb_dns_name>/
```
Expected response:
```http
HTTP/1.1 301 Moved Permanently
Server: awselb/2.0
Location: https://<alb_dns_name>:443/
```

### Testing the Verified HTTPS Endpoint
```bash
curl -kv https://<alb_dns_name>/healthz
```
Expected output:
```json
{
  "status": "healthy",
  "service": "CloudDocs",
  "version": "1.0.0",
  "mode": "AWS Production Cloud",
  "database": "RDS MySQL Multi-AZ",
  "storage": "AWS S3 Private Bucket",
  "timestamp": "2026-10-06T18:30:00Z"
}
```

---

## Local Development & Mock Testing

CloudDocs includes a built-in **Local Mock Mode** allowing full local validation without active AWS credentials or a running MySQL instance:

### Option 1: Run with Python Virtual Environment
```bash
# 1. Install dependencies
pip install -r app/requirements.txt

# 2. Run local runner (auto-initializes SQLite and local mock vault)
python scripts/local_run.py
```
Open **`http://localhost:8000`** in your browser.

### Option 2: Run with Docker
```bash
docker build -t clouddocs:local -f app/Dockerfile app/
docker run -p 8000:8000 -e MOCK_MODE=true clouddocs:local
```

### Option 3: Run Automated Test Suite
```bash
pytest app/test_app.py -v
```

All test cases (Health check, Dashboard rendering, Upload multipart stream, Presigned download retrieval, Delete operation) will run in isolated local mode.

---

## CI/CD Pipeline Details

The GitHub Actions pipeline is configured in `.github/workflows/terraform-ci-cd.yml` and consists of three stages:

1. **`lint-and-validate`**:
   - Triggers on every push and pull request to `main`.
   - Runs `terraform fmt -check -recursive` to enforce HashiCorp style standards.
   - Runs `terraform init -backend=false` and `terraform validate`.
2. **`terraform-plan`**:
   - Authenticates to AWS using GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
   - Generates speculative plan (`terraform plan -out=tfplan`).
   - Attaches the plan summary as a comment directly to the Pull Request.
3. **`terraform-apply`**:
   - Runs **strictly upon merge** into the `main` branch.
   - Requires deployment approval when paired with GitHub Environment protection rules.
   - Executes `terraform apply -auto-approve tfplan` to provision or update infrastructure.

---

## Teardown & Clean-up

To avoid unnecessary AWS cloud charges after completing the evaluation:

```bash
cd terraform

# Destroy all provisioned resources
terraform destroy -auto-approve
```
*(Ensure `force_destroy_s3 = true` in `terraform.tfvars` if you uploaded test files into the S3 bucket during testing).*
