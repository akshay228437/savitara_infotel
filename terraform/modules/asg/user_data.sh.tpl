#!/bin/bash
set -euo pipefail

# Log everything to console and /var/log/user-data.log for debugging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting CloudDocs Docker Container Setup"
echo "=========================================="

# 1. Install & start Docker
dnf update -y
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# 2. Pull from Docker Hub & Run
# Replace <your-dockerhub-username>/clouddocs:latest with your image
DOCKER_IMAGE="akshy22/clouddocs:latest"

docker pull "$DOCKER_IMAGE"

docker run -d \
  --name clouddocs \
  --restart always \
  --network host \
  -e PORT=8000 \
  -e MOCK_MODE=false \
  -e AWS_REGION="${aws_region}" \
  -e DOCUMENT_BUCKET_NAME="${document_bucket_name}" \
  -e SECRET_ARN_DB="${db_secret_arn}" \
  "$DOCKER_IMAGE"

# 3. Wait and verify health check
sleep 5
curl -sf http://127.0.0.1:8000/healthz || echo "Health check starting up..."
echo "Container started successfully!"