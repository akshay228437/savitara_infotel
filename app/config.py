"""CloudDocs - Application Configuration Module.

Reads configuration parameters from environment variables with sensible defaults
and provides automated detection for local development mock mode.
"""

import os
from dataclasses import dataclass


@dataclass
class Settings:
    # Service Information
    APP_NAME: str = "CloudDocs Enterprise Vault"
    APP_VERSION: str = "1.0.0"
    ENVIRONMENT: str = os.getenv("APP_ENV", os.getenv("ENVIRONMENT", "development"))
    DEBUG: bool = os.getenv("DEBUG", "false").lower() in ("true", "1", "yes")

    # Networking / Server
    HOST: str = os.getenv("HOST", "0.0.0.0")
    PORT: int = int(os.getenv("PORT", "8000"))

    # AWS Configuration
    AWS_REGION: str = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
    DOCUMENT_BUCKET_NAME: str = os.getenv("DOCUMENT_BUCKET_NAME", "clouddocs-prod-documents-vault")
    SECRET_ARN_DB: str = os.getenv("SECRET_ARN_DB", "")

    # Direct Database fallback configuration (if not using Secrets Manager in local dev)
    DB_HOST: str = os.getenv("DB_HOST", "localhost")
    DB_PORT: int = int(os.getenv("DB_PORT", "3306"))
    DB_USER: str = os.getenv("DB_USER", "clouddocs_admin")
    DB_PASSWORD: str = os.getenv("DB_PASSWORD", "")
    DB_NAME: str = os.getenv("DB_NAME", "clouddocs_db")

    # Local Storage & Mock Mode
    MOCK_MODE: bool = os.getenv("MOCK_MODE", "").lower() in ("true", "1", "yes")
    LOCAL_STORAGE_DIR: str = os.getenv("LOCAL_STORAGE_DIR", os.path.join(os.path.dirname(__file__), "storage_mock"))
    LOCAL_SQLITE_PATH: str = os.getenv("LOCAL_SQLITE_PATH", os.path.join(os.path.dirname(__file__), "clouddocs_local.db"))

    # Presigned URL Expiration in seconds (default 15 minutes)
    PRESIGNED_URL_EXPIRATION: int = int(os.getenv("PRESIGNED_URL_EXPIRATION", "900"))


settings = Settings()
