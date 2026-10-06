# =============================================================================
# CloudDocs Containerfile - Multi-stage Production Build
# =============================================================================

# Build stage
FROM python:3.11-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Final Runtime stage
FROM python:3.11-slim AS runner

WORKDIR /app

# Install runtime dependencies for MySQL client
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Create dedicated non-root application user
RUN groupadd -g 1001 clouddocs && \
    useradd -u 1001 -g clouddocs -m -s /bin/bash clouddocs

# Copy dependencies from builder
COPY --from=builder /root/.local /home/clouddocs/.local
ENV PATH=/home/clouddocs/.local/bin:$PATH

# Copy application source code
COPY --chown=clouddocs:clouddocs . /app/app
WORKDIR /app

# Create storage and data directories
RUN mkdir -p /app/app/storage_mock && \
    chown -R clouddocs:clouddocs /app

USER clouddocs

EXPOSE 8000

ENV PORT=8000 \
    HOST=0.0.0.0 \
    PYTHONUNBUFFERED=1 \
    MOCK_MODE=false

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/healthz || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--access-log"]
