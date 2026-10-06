"""CloudDocs Database Layer.

Provides MySQL database connectivity via PyMySQL with dynamic credential resolution
from AWS Secrets Manager. Includes an automatic SQLite fallback for local testing.
"""

import json
import logging
import sqlite3
from datetime import datetime
from typing import Any, Dict, List, Optional
import pymysql
import pymysql.cursors

from app.config import settings

logger = logging.getLogger("clouddocs.db")
logging.basicConfig(level=logging.INFO)

# Cached database credentials from AWS Secrets Manager
_cached_credentials: Optional[Dict[str, Any]] = None
_is_using_sqlite: bool = False


def fetch_secrets_manager_credentials() -> Optional[Dict[str, Any]]:
    """Retrieve database connection credentials from AWS Secrets Manager."""
    global _cached_credentials
    if _cached_credentials is not None:
        return _cached_credentials

    if not settings.SECRET_ARN_DB or settings.MOCK_MODE:
        logger.info("Using local or manual database configuration (MOCK_MODE or no SECRET_ARN_DB).")
        return None

    try:
        import boto3
        from botocore.exceptions import ClientError

        client = boto3.client("secretsmanager", region_name=settings.AWS_REGION)
        logger.info("Fetching database credentials from AWS Secrets Manager: %s", settings.SECRET_ARN_DB)
        response = client.get_secret_value(SecretId=settings.SECRET_ARN_DB)

        if "SecretString" in response:
            secret_data = json.loads(response["SecretString"])
            _cached_credentials = secret_data
            logger.info("Successfully fetched and cached credentials for host: %s", secret_data.get("host"))
            return _cached_credentials
    except Exception as exc:
        logger.warning("Failed to fetch credentials from AWS Secrets Manager: %s", exc)

    return None


def get_connection():
    """Establish and return an active database connection (MySQL or SQLite fallback)."""
    global _is_using_sqlite

    # If mock mode is explicitly forced, use SQLite immediately
    if settings.MOCK_MODE:
        _is_using_sqlite = True
        conn = sqlite3.connect(settings.LOCAL_SQLITE_PATH)
        conn.row_factory = sqlite3.Row
        return conn

    # Attempt MySQL connection using Secrets Manager or configured environment vars
    creds = fetch_secrets_manager_credentials()
    host = creds.get("host", settings.DB_HOST) if creds else settings.DB_HOST
    port = int(creds.get("port", settings.DB_PORT)) if creds else settings.DB_PORT
    user = creds.get("username", settings.DB_USER) if creds else settings.DB_USER
    password = creds.get("password", settings.DB_PASSWORD) if creds else settings.DB_PASSWORD
    dbname = creds.get("dbname", settings.DB_NAME) if creds else settings.DB_NAME

    try:
        conn = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=dbname,
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=5,
            autocommit=True,
        )
        _is_using_sqlite = False
        return conn
    except Exception as exc:
        logger.warning(
            "MySQL connection failed (%s). Falling back to local SQLite database at: %s",
            exc,
            settings.LOCAL_SQLITE_PATH,
        )
        _is_using_sqlite = True
        conn = sqlite3.connect(settings.LOCAL_SQLITE_PATH)
        conn.row_factory = sqlite3.Row
        return conn


def init_db():
    """Initialize database tables for CloudDocs."""
    conn = get_connection()
    try:
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS documents (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    filename TEXT NOT NULL,
                    s3_key TEXT NOT NULL UNIQUE,
                    file_size INTEGER NOT NULL,
                    content_type TEXT NOT NULL,
                    uploader TEXT NOT NULL,
                    category TEXT NOT NULL,
                    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
            )
            conn.commit()
            logger.info("Initialized SQLite database schema successfully.")
        else:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                    CREATE TABLE IF NOT EXISTS documents (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        filename VARCHAR(255) NOT NULL,
                        s3_key VARCHAR(512) NOT NULL UNIQUE,
                        file_size BIGINT NOT NULL,
                        content_type VARCHAR(128) NOT NULL DEFAULT 'application/octet-stream',
                        uploader VARCHAR(100) NOT NULL DEFAULT 'System',
                        category VARCHAR(50) NOT NULL DEFAULT 'General',
                        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
                    """
                )
            logger.info("Initialized RDS MySQL database schema successfully.")
    finally:
        conn.close()


def insert_document(
    filename: str,
    s3_key: str,
    file_size: int,
    content_type: str,
    uploader: str,
    category: str,
) -> int:
    """Insert a new document metadata record and return its generated ID."""
    conn = get_connection()
    try:
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute(
                """
                INSERT INTO documents (filename, s3_key, file_size, content_type, uploader, category, uploaded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (filename, s3_key, file_size, content_type, uploader, category, datetime.utcnow()),
            )
            conn.commit()
            return cursor.lastrowid
        else:
            with conn.cursor() as cursor:
                cursor.execute(
                    """
                    INSERT INTO documents (filename, s3_key, file_size, content_type, uploader, category, uploaded_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (filename, s3_key, file_size, content_type, uploader, category, datetime.utcnow()),
                )
                return cursor.lastrowid
    finally:
        conn.close()


def list_documents() -> List[Dict[str, Any]]:
    """Retrieve all document metadata records ordered by newest first."""
    conn = get_connection()
    try:
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM documents ORDER BY uploaded_at DESC")
            rows = cursor.fetchall()
            return [dict(row) for row in rows]
        else:
            with conn.cursor() as cursor:
                cursor.execute("SELECT * FROM documents ORDER BY uploaded_at DESC")
                return cursor.fetchall()
    finally:
        conn.close()


def get_document_by_id(doc_id: int) -> Optional[Dict[str, Any]]:
    """Fetch single document metadata row by ID."""
    conn = get_connection()
    try:
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM documents WHERE id = ?", (doc_id,))
            row = cursor.fetchone()
            return dict(row) if row else None
        else:
            with conn.cursor() as cursor:
                cursor.execute("SELECT * FROM documents WHERE id = %s", (doc_id,))
                return cursor.fetchone()
    finally:
        conn.close()


def delete_document(doc_id: int) -> bool:
    """Remove a document record from the database."""
    conn = get_connection()
    try:
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM documents WHERE id = ?", (doc_id,))
            conn.commit()
            return cursor.rowcount > 0
        else:
            with conn.cursor() as cursor:
                cursor.execute("DELETE FROM documents WHERE id = %s", (doc_id,))
                return cursor.rowcount > 0
    finally:
        conn.close()


def check_db_health() -> Dict[str, Any]:
    """Test database connectivity and return status details."""
    try:
        conn = get_connection()
        if _is_using_sqlite:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            conn.close()
            return {"status": "connected", "engine": "SQLite (Local Mock)"}
        else:
            with conn.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            conn.close()
            return {"status": "connected", "engine": "RDS MySQL Multi-AZ"}
    except Exception as exc:
        return {"status": "degraded", "error": str(exc), "engine": "offline"}
