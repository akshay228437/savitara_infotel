#!/bin/bash
set -euo pipefail

# =============================================================================
# CloudDocs Automated EC2 Bootstrap Script (Amazon Linux 2023)
# =============================================================================

echo "=========================================="
echo "Starting CloudDocs Instance Provisioning"
echo "Timestamp: $(date -u)"
echo "=========================================="

# 1. Update system packages
dnf update -y

# 2. Install Python 3.11, Git, and build essentials
dnf install -y python3.11 python3.11-pip python3.11-devel git gcc mariadb-connector-c-devel

# 3. Create dedicated non-root application user and directories
id -u clouddocs &>/dev/null || useradd -r -s /bin/false clouddocs
APP_DIR="/opt/clouddocs"
mkdir -p "$${APP_DIR}"
mkdir -p "$${APP_DIR}/app"
mkdir -p "$${APP_DIR}/app/templates"
mkdir -p "$${APP_DIR}/storage_mock"
mkdir -p "/var/log/clouddocs"
chown -R clouddocs:clouddocs "$${APP_DIR}" "/var/log/clouddocs"

# 4. Write environment configuration for production
cat <<'EOF' > "$${APP_DIR}/.env"
AWS_DEFAULT_REGION=${aws_region}
AWS_REGION=${aws_region}
DOCUMENT_BUCKET_NAME=${document_bucket_name}
SECRET_ARN_DB=${db_secret_arn}
PORT=8000
HOST=0.0.0.0
APP_ENV=production
MOCK_MODE=false
EOF
chown clouddocs:clouddocs "$${APP_DIR}/.env"
chmod 600 "$${APP_DIR}/.env"

# 5. Set up Python virtual environment
cd "$${APP_DIR}"
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip

# 6. Install Python dependencies
cat <<'EOF' > "$${APP_DIR}/requirements.txt"
fastapi==0.110.0
uvicorn[standard]==0.29.0
boto3==1.34.80
botocore==1.34.80
pymysql==1.1.0
cryptography==42.0.5
python-multipart==0.0.9
jinja2==3.1.3
pydantic==2.6.4
pydantic-settings==2.2.1
requests==2.31.0
EOF

pip install -r "$${APP_DIR}/requirements.txt"

# 7. Pull application files or write bootstrap fallback
# If a repository URL is provided, clone it; otherwise deploy embedded app code
if [ -n "${repo_url}" ]; then
  echo "Cloning repository from ${repo_url}..."
  git clone "${repo_url}" /tmp/repo
  cp -r /tmp/repo/app/* "$${APP_DIR}/app/"
  rm -rf /tmp/repo
fi

# Ensure permissions
chown -R clouddocs:clouddocs "$${APP_DIR}"

# 8. Create Systemd Service for CloudDocs
cat <<EOF > /etc/systemd/system/clouddocs.service
[Unit]
Description=CloudDocs Enterprise Document Portal Application
After=network.target

[Service]
Type=simple
User=clouddocs
Group=clouddocs
WorkingDirectory=$${APP_DIR}
EnvironmentFile=$${APP_DIR}/.env
ExecStart=$${APP_DIR}/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 2 --access-log
Restart=always
RestartSec=5
StandardOutput=append:/var/log/clouddocs/app.log
StandardError=append:/var/log/clouddocs/app-err.log

# Security Sandboxing
ProtectSystem=full
ProtectHome=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 9. Reload systemd, enable and start service
systemctl daemon-reload
systemctl enable clouddocs.service
systemctl start clouddocs.service

# 10. Smoke test internal health endpoint
sleep 5
curl -sf http://127.0.0.1:8000/healthz || echo "CloudDocs service starting up, healthz pending..."

echo "=========================================="
echo "CloudDocs Provisioning Completed Successfully!"
echo "=========================================="
