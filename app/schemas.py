"""Data schemas and Pydantic validation models for CloudDocs."""

from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class DocumentCreate(BaseModel):
    filename: str = Field(..., min_length=1, max_length=255)
    s3_key: str
    file_size: int = Field(..., ge=0)
    content_type: str = "application/octet-stream"
    uploader: str = Field(default="Anonymous", max_length=100)
    category: str = Field(default="General", max_length=50)


class DocumentResponse(BaseModel):
    id: int
    filename: str
    s3_key: str
    file_size: int
    content_type: str
    uploader: str
    category: str
    uploaded_at: datetime
    formatted_size: Optional[str] = None
    download_url: Optional[str] = None

    class Config:
        from_attributes = True


class HealthResponse(BaseModel):
    status: str = "healthy"
    service: str = "CloudDocs"
    version: str = "1.0.0"
    mode: str
    database: str
    storage: str
    timestamp: str
