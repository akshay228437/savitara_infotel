# CloudDocs — Manual Infrastructure Provisioning & Deployment Runbook

This guide provides a comprehensive, step-by-step procedure to manually provision the AWS infrastructure and deploy the **CloudDocs** application via the **AWS Management Console** or **AWS CLI** without running Terraform.

---

## Architecture Specification Quick Reference

| Resource | Value / CIDR / Configuration |
| :--- | :--- |
| **AWS Region** | `us-east-1` (or your preferred region) |
| **VPC CIDR** | `10.0.0.0/16` |
| **Public Subnets (2 AZs)** | `10.0.1.0/24` (`us-east-1a`), `10.0.2.0/24` (`us-east-1b`) |
| **Private App Subnets (2 AZs)** | `10.0.11.0/24` (`us-east-1a`), `10.0.12.0/24` (`us-east-1b`) |
| **Isolated DB Subnets (2 AZs)**| `10.0.21.0/24` (`us-east-1a`), `10.0.22.0/24` (`us-east-1b`) |
| **App Port** | `8000` (FastAPI / Uvicorn) |
| **Health Check Path** | `/healthz` (HTTP 200) |
| **Database Engine** | MySQL 8.0 (Multi-AZ, `db.t3.micro`) |

---

## Step 1: Networking Setup (VPC, Subnets, Gateways, Route Tables)

### 1.1 Create the VPC
1. Navigate to **VPC Console** &rarr; **Your VPCs** &rarr; **Create VPC**.
2. Select **VPC only**.
3. **Name tag**: `clouddocs-prod-vpc`.
4. **IPv4 CIDR block**: `10.0.0.0/16`.
5. Click **Create VPC**.
6. Select the created VPC &rarr; **Actions** &rarr; **Edit VPC settings** &rarr; Enable **DNS hostnames** &rarr; **Save changes**.

---

### 1.2 Create the 6 Subnets
Navigate to **VPC Console** &rarr; **Subnets** &rarr; **Create subnet** (select `clouddocs-prod-vpc`):

| Subnet Name | Availability Zone | IPv4 CIDR Block | Auto-assign Public IP |
| :--- | :--- | :--- | :--- |
| `clouddocs-public-1` | `us-east-1a` | `10.0.1.0/24` | **Yes** (Enable in Subnet settings) |
| `clouddocs-public-2` | `us-east-1b` | `10.0.2.0/24` | **Yes** (Enable in Subnet settings) |
| `clouddocs-private-app-1` | `us-east-1a` | `10.0.11.0/24` | No |
| `clouddocs-private-app-2` | `us-east-1b` | `10.0.12.0/24` | No |
| `clouddocs-private-db-1` | `us-east-1a` | `10.0.21.0/24` | No |
| `clouddocs-private-db-2` | `us-east-1b` | `10.0.22.0/24` | No |

---

### 1.3 Create Internet Gateway & NAT Gateway
1. **Internet Gateway**:
   * Navigate to **Internet Gateways** &rarr; **Create internet gateway** &rarr; Name: `clouddocs-igw`.
   * Click **Actions** &rarr; **Attach to VPC** &rarr; Select `clouddocs-prod-vpc`.
2. **Elastic IP for NAT**:
   * Navigate to **Elastic IPs** &rarr; **Allocate Elastic IP** &rarr; Name: `clouddocs-nat-eip`.
3. **NAT Gateway**:
   * Navigate to **NAT Gateways** &rarr; **Create NAT gateway**.
   * Name: `clouddocs-nat-gw`.
   * Subnet: Select `clouddocs-public-1`.
   * Allocation ID: Select `clouddocs-nat-eip`.
   * Click **Create NAT gateway** (takes ~1-2 minutes).

---

### 1.4 Configure Route Tables
1. **Public Route Table (`clouddocs-public-rt`)**:
   * Create route table &rarr; Name: `clouddocs-public-rt` &rarr; VPC: `clouddocs-prod-vpc`.
   * Under **Routes** &rarr; **Edit routes** &rarr; Add route `0.0.0.0/0` with Target `Internet Gateway` (`clouddocs-igw`).
   * Under **Subnet associations** &rarr; Associate `clouddocs-public-1` and `clouddocs-public-2`.
2. **Private App Route Table (`clouddocs-private-app-rt`)**:
   * Create route table &rarr; Name: `clouddocs-private-app-rt` &rarr; VPC: `clouddocs-prod-vpc`.
   * Under **Routes** &rarr; **Edit routes** &rarr; Add route `0.0.0.0/0` with Target `NAT Gateway` (`clouddocs-nat-gw`).
   * Under **Subnet associations** &rarr; Associate `clouddocs-private-app-1` and `clouddocs-private-app-2`.
3. **Private Database Route Table (`clouddocs-private-db-rt`)**:
   * Create route table &rarr; Name: `clouddocs-private-db-rt` &rarr; VPC: `clouddocs-prod-vpc`.
   * **Keep routes strictly local** (Do **NOT** add any `0.0.0.0/0` route! This ensures total database isolation).
   * Under **Subnet associations** &rarr; Associate `clouddocs-private-db-1` and `clouddocs-private-db-2`.

---

## Step 2: Storage Setup (S3 Document Vault & ALB Logs)

### 2.1 Create Document Storage Bucket
1. Open **S3 Console** &rarr; **Create bucket**.
2. **Bucket name**: `clouddocs-documents-<your-account-id>-vault` (must be globally unique).
3. **Region**: `us-east-1`.
4. **Block Public Access**: Keep **Block all public access** checked (Enabled).
5. **Bucket Versioning**: Select **Enable**.
6. **Default encryption**:
   * Encryption type: **Server-side encryption with Amazon S3 managed keys (SSE-S3)** or **AWS KMS**.
   * Bucket Key: **Enable**.
7. Click **Create bucket**.
8. **Enforce HTTPS in Bucket Policy**:
   * Open the created bucket &rarr; **Permissions** &rarr; **Bucket policy** &rarr; **Edit**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "EnforceTLSRequestsOnly",
         "Effect": "Deny",
         "Principal": "*",
         "Action": "s3:*",
         "Resource": [
           "arn:aws:s3:::<YOUR_DOCUMENT_BUCKET_NAME>",
           "arn:aws:s3:::<YOUR_DOCUMENT_BUCKET_NAME>/*"
         ],
         "Condition": {
           "Bool": {
             "aws:SecureTransport": "false"
           }
         }
       }
     ]
   }
   ```

---

## Step 3: Security Groups Setup (Isolation Chain)

Navigate to **EC2 Console** &rarr; **Security Groups** &rarr; **Create security group**:

### 3.1 ALB Security Group (`clouddocs-alb-sg`)
* **VPC**: `clouddocs-prod-vpc`
* **Inbound Rules**:
  * Type: `HTTP` | Port: `80` | Source: `0.0.0.0/0`
  * Type: `HTTPS` | Port: `443` | Source: `0.0.0.0/0`
* **Outbound Rules**:
  * Type: `Custom TCP` | Port: `8000` | Destination: `10.0.0.0/16` (or EC2 App SG)

---

### 3.2 EC2 App Security Group (`clouddocs-ec2-app-sg`)
* **VPC**: `clouddocs-prod-vpc`
* **Inbound Rules**:
  * Type: `Custom TCP` | Port: `8000` | Source: `clouddocs-alb-sg`
* **Outbound Rules**:
  * Type: `MySQL/Aurora` | Port: `3306` | Destination: `10.0.0.0/16` (or RDS SG)
  * Type: `HTTPS` | Port: `443` | Destination: `0.0.0.0/0` (for AWS SDK & dnf)
  * Type: `HTTP` | Port: `80` | Destination: `0.0.0.0/0` (for OS packages)

---

### 3.3 RDS Security Group (`clouddocs-rds-sg`)
* **VPC**: `clouddocs-prod-vpc`
* **Inbound Rules**:
  * Type: `MySQL/Aurora` | Port: `3306` | Source: `clouddocs-ec2-app-sg`
* **Outbound Rules**:
  * Remove default outbound rule (No egress required).

---

## Step 4: IAM Instance Profile Setup

1. Open **IAM Console** &rarr; **Roles** &rarr; **Create role**.
2. **Trusted entity type**: **AWS service** &rarr; Use case: **EC2**.
3. **Permissions**:
   * Attach managed policy: `AmazonSSMManagedInstanceCore` (allows AWS Systems Manager session access without SSH ports).
4. **Create Custom Least-Privilege Inline Policy** (Name: `CloudDocsAppPolicy`):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "S3DocumentAccess",
         "Effect": "Allow",
         "Action": [
           "s3:ListBucket",
           "s3:GetBucketLocation",
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject"
         ],
         "Resource": [
           "arn:aws:s3:::<YOUR_DOCUMENT_BUCKET_NAME>",
           "arn:aws:s3:::<YOUR_DOCUMENT_BUCKET_NAME>/*"
         ]
       },
       {
         "Sid": "SecretsManagerAccess",
         "Effect": "Allow",
         "Action": [
           "secretsmanager:GetSecretValue",
           "secretsmanager:DescribeSecret"
         ],
         "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:clouddocs/prod/*"
       },
       {
         "Sid": "CloudWatchLogging",
         "Effect": "Allow",
         "Action": [
           "logs:CreateLogGroup",
           "logs:CreateLogStream",
           "logs:PutLogEvents"
         ],
         "Resource": "arn:aws:logs:*:*:*"
       }
     ]
   }
   ```
5. **Role name**: `clouddocs-ec2-role`. Click **Create role**.
*(Note: IAM automatically creates an Instance Profile with the same name `clouddocs-ec2-role`).*

---

## Step 5: AWS Secrets Manager & RDS MySQL Setup

### 5.1 Store Database Secret
1. Open **AWS Secrets Manager Console** &rarr; **Store a new secret**.
2. **Secret type**: Select **Other type of secret**.
3. **Key/value pairs**:
   * `engine`: `mysql`
   * `host`: `localhost` *(We will update this with the real RDS host once RDS finishes creating)*
   * `port`: `3306`
   * `username`: `clouddocs_admin`
   * `password`: `<Generate-A-Strong-20-Char-Password>`
   * `dbname`: `clouddocs_db`
4. **Secret name**: `clouddocs/prod/rds-mysql-credentials`.
5. Click **Next** &rarr; Disable automatic rotation for now &rarr; **Store**.
6. **Copy the Secret ARN** (e.g. `arn:aws:secretsmanager:us-east-1:123456789012:secret:clouddocs/prod/rds-mysql-credentials-abc123`).

---

### 5.2 Create RDS DB Subnet Group
1. Open **RDS Console** &rarr; **Subnet groups** &rarr; **Create DB subnet group**.
2. **Name**: `clouddocs-db-subnet-group`.
3. **VPC**: `clouddocs-prod-vpc`.
4. **Availability Zones**: Choose `us-east-1a` and `us-east-1b`.
5. **Subnets**: Select `clouddocs-private-db-1` (`10.0.21.0/24`) and `clouddocs-private-db-2` (`10.0.22.0/24`).
6. Click **Create**.

---

### 5.3 Launch RDS MySQL Multi-AZ Instance
1. Open **RDS Console** &rarr; **Databases** &rarr; **Create database**.
2. **Engine type**: **MySQL** &rarr; Engine Version: **8.0.x**.
3. **Templates**: **Production** (or Dev/Test for lower cost).
4. **Availability & durability**: Select **Multi-AZ DB instance** (High availability).
5. **Settings**:
   * DB instance identifier: `clouddocs-prod-mysql`
   * Master username: `clouddocs_admin`
   * Master password: `<Enter the password configured in Secrets Manager>`
6. **Instance configuration**: `db.t3.micro` (or `db.t4g.micro`).
7. **Storage**: `gp3`, 20 GiB, Enable storage autoscaling.
8. **Connectivity**:
   * VPC: `clouddocs-prod-vpc`
   * DB Subnet Group: `clouddocs-db-subnet-group`
   * Public access: **No**
   * Existing VPC security groups: Select `clouddocs-rds-sg` (remove default).
9. **Additional configuration**:
   * Initial database name: `clouddocs_db`
   * Encryption: Enable encryption.
10. Click **Create database** (~5-10 minutes).
11. **Update Secret Host**: Once available, copy the **Endpoint** (e.g. `clouddocs-prod-mysql.xxxx.us-east-1.rds.amazonaws.com`). Go back to **Secrets Manager** &rarr; Edit secret values &rarr; update `host` to this endpoint address.

---

## Step 6: Application Load Balancer (ALB) Setup

### 6.1 Create Target Group
1. Open **EC2 Console** &rarr; **Target Groups** &rarr; **Create target group**.
2. **Target type**: **Instances**.
3. **Target group name**: `clouddocs-tg`.
4. **Protocol**: `HTTP` | **Port**: `8000`.
5. **VPC**: Select `clouddocs-prod-vpc`.
6. **Health checks**:
   * Health check protocol: `HTTP`
   * Health check path: `/healthz`
   * Healthy threshold: `2`
   * Interval: `30 seconds`
7. Click **Next** &rarr; Click **Create target group** (without registering targets yet).

---

### 6.2 Create the ALB
1. Open **EC2 Console** &rarr; **Load Balancers** &rarr; **Create load balancer** &rarr; **Application Load Balancer**.
2. **Name**: `clouddocs-prod-alb`.
3. **Scheme**: **Internet-facing** | IP address type: IPv4.
4. **Network mapping**:
   * VPC: `clouddocs-prod-vpc`
   * Mappings: Check `us-east-1a` (select `clouddocs-public-1`) and `us-east-1b` (select `clouddocs-public-2`).
5. **Security groups**: Select `clouddocs-alb-sg`.
6. **Listeners and routing**:
   * If you have an ACM Certificate:
     * Listener 1: Port `80` (HTTP) &rarr; Set default action to **Redirect** &rarr; Port `443`, Protocol `HTTPS`, Status code `301`.
     * Listener 2: Add listener Port `443` (HTTPS) &rarr; Forward to `clouddocs-tg` &rarr; Attach your ACM SSL Certificate.
   * If testing without SSL domain initially:
     * Listener: Port `80` (HTTP) &rarr; Forward to `clouddocs-tg`.
7. Click **Create load balancer**.

---

## Step 7: Launch Template & Auto Scaling Group Setup

### 7.1 Create Launch Template
1. Open **EC2 Console** &rarr; **Launch Templates** &rarr; **Create launch template**.
2. **Template name**: `clouddocs-prod-lt`.
3. **Application and OS Images (AMI)**: **Amazon Linux 2023 AMI** (x86_64).
4. **Instance type**: `t3.micro`.
5. **Key pair**: Optional (Use AWS Systems Manager Session Manager instead).
6. **Network settings**:
   * Security groups: Select `clouddocs-ec2-app-sg`.
7. **Storage (Volumes)**: 20 GiB gp3, **Encrypted**.
8. **Advanced details**:
   * **IAM instance profile**: Select `clouddocs-ec2-role`.
   * **Metadata accessible**: Enabled.
   * **Metadata version**: **V2 only (token required)** (Enforces IMDSv2).
   * **User data** (Paste the bootstrap script below, replacing `<YOUR_REGION>`, `<YOUR_DOCUMENT_BUCKET_NAME>`, and `<YOUR_SECRET_ARN>`):

```bash
#!/bin/bash
set -euo pipefail

echo "Starting CloudDocs Instance Provisioning..."

# 1. Update and install dependencies
dnf update -y
dnf install -y python3.11 python3.11-pip git gcc mariadb-connector-c-devel

# 2. Setup application directories
APP_DIR="/opt/clouddocs"
mkdir -p "${APP_DIR}/app"
mkdir -p "${APP_DIR}/app/templates"
mkdir -p "${APP_DIR}/storage_mock"
mkdir -p "/var/log/clouddocs"

# 3. Environment configuration
cat <<'EOF' > "${APP_DIR}/.env"
AWS_DEFAULT_REGION=us-east-1
AWS_REGION=us-east-1
DOCUMENT_BUCKET_NAME=<YOUR_DOCUMENT_BUCKET_NAME>
SECRET_ARN_DB=<YOUR_SECRET_ARN>
PORT=8000
HOST=0.0.0.0
APP_ENV=production
MOCK_MODE=false
EOF

# 4. Clone or pull CloudDocs repository
cd "${APP_DIR}"
git clone https://github.com/<YOUR_USER>/<YOUR_REPO>.git /tmp/repo
cp -r /tmp/repo/app/* "${APP_DIR}/app/"
rm -rf /tmp/repo

# 5. Virtualenv & Python dependencies
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install fastapi uvicorn[standard] boto3 botocore pymysql cryptography python-multipart jinja2 pydantic-settings

# 6. Systemd service configuration
cat <<EOF > /etc/systemd/system/clouddocs.service
[Unit]
Description=CloudDocs Enterprise Portal
After=network.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${APP_DIR}/.env
ExecStart=${APP_DIR}/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --access-log
Restart=always
RestartSec=5
StandardOutput=append:/var/log/clouddocs/app.log
StandardError=append:/var/log/clouddocs/app-err.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable clouddocs.service
systemctl start clouddocs.service
```

9. Click **Create launch template**.

---

### 7.2 Create Auto Scaling Group
1. Open **EC2 Console** &rarr; **Auto Scaling Groups** &rarr; **Create Auto Scaling group**.
2. **Name**: `clouddocs-prod-asg`.
3. **Launch template**: Select `clouddocs-prod-lt`. Click **Next**.
4. **Network**:
   * VPC: `clouddocs-prod-vpc`.
   * Subnets: Select `clouddocs-private-app-1` and `clouddocs-private-app-2`. Click **Next**.
5. **Load balancing**:
   * Select **Attach to an existing load balancer**.
   * Choose **Attach to your target group** &rarr; Select `clouddocs-tg`.
   * Health checks: Check **Elastic Load Balancing (ELB)** health checks.
   * Health check grace period: `300` seconds. Click **Next**.
6. **Group size & scaling policies**:
   * Desired capacity: `2`
   * Minimum capacity: `2`
   * Maximum capacity: `4`
   * Scaling policies: **Target tracking scaling policy** &rarr; Metric: Average CPU utilization &rarr; Target value: `70%`.
7. Click **Next** &rarr; Click **Create Auto Scaling group**.

---

## Step 8: Verification & Health Check

1. **Verify Target Group Health**:
   * Navigate to **Target Groups** &rarr; Select `clouddocs-tg` &rarr; Open **Targets** tab.
   * Once instances finish bootstrapping (~2-3 mins), both registered instances should show status **Healthy** (200 OK from `/healthz`).
2. **Access the Application**:
   * Copy the **DNS name** from your Application Load Balancer (e.g. `clouddocs-prod-alb-123456789.us-east-1.elb.amazonaws.com`).
   * Open in browser: `http://<alb-dns-name>` or `https://<alb-dns-name>`.
   * The CloudDocs dashboard will load displaying:
     * Status badges: `ALB: HTTPS Active`, `Database: RDS MySQL Multi-AZ`, `Vault: AWS S3 Private Bucket`.
3. **Functional Testing**:
   * Upload a document via the **Upload Document** modal.
   * Confirm the file appears in the dashboard inventory.
   * Click **Download** &rarr; verify temporary 15-minute presigned S3 URL redirect and download.
   * Verify object in S3 Console: Go to S3 &rarr; `<YOUR_DOCUMENT_BUCKET_NAME>` &rarr; check that `documents/<uuid>_<filename>` is present and encrypted.
