-- =============================================================================
-- CloudDocs Enterprise Vault - MySQL Schema Initialization
-- Automatically provisioned or manually executed against RDS MySQL
-- =============================================================================

CREATE DATABASE IF NOT EXISTS clouddocs_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE clouddocs_db;

CREATE TABLE IF NOT EXISTS documents (
  id INT AUTO_INCREMENT PRIMARY KEY,
  filename VARCHAR(255) NOT NULL COMMENT 'Original client filename',
  s3_key VARCHAR(512) NOT NULL UNIQUE COMMENT 'S3 object key path inside bucket',
  file_size BIGINT NOT NULL COMMENT 'Payload size in bytes',
  content_type VARCHAR(128) NOT NULL DEFAULT 'application/octet-stream' COMMENT 'MIME type of document',
  uploader VARCHAR(100) NOT NULL DEFAULT 'System' COMMENT 'Identity or username of uploader',
  category VARCHAR(50) NOT NULL DEFAULT 'General' COMMENT 'Corporate document classification',
  uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Upload timestamp in UTC',
  INDEX idx_category (category),
  INDEX idx_uploaded_at (uploaded_at),
  INDEX idx_uploader (uploader)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
