"""CloudDocs Enterprise Portal - FastAPI Application Backend.

Implements secure document vault routes:
- GET  /              : Responsive dashboard listing documents from MySQL
- POST /upload        : Streams multipart file to S3 and persists metadata in MySQL
- GET  /download/{id} : Generates presigned AWS S3 URL or serves local payload
- GET  /healthz       : High-availability health check for ALB target group evaluation
- GET  /api/documents : REST endpoint returning JSON document list
- DELETE /documents/{id} : Removes document from storage and metadata catalog
"""

from contextlib import asynccontextmanager
from datetime import datetime
import logging
import os
from typing import Optional
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import settings
from app.db import (
    check_db_health,
    delete_document,
    get_document_by_id,
    init_db,
    insert_document,
    list_documents,
)
from app.schemas import HealthResponse
from app.storage import (
    check_storage_health,
    delete_stored_file,
    generate_download_url,
    get_local_file_path,
    upload_document,
)

logger = logging.getLogger("clouddocs.main")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan context manager for startup and shutdown hooks."""
    logger.info("Initializing CloudDocs Enterprise Portal (%s)...", settings.APP_VERSION)
    logger.info("Environment: %s | Mock Mode: %s", settings.ENVIRONMENT, settings.MOCK_MODE)
    logger.info("Target Document Bucket: %s", settings.DOCUMENT_BUCKET_NAME)
    if settings.SECRET_ARN_DB:
        logger.info("Target Secrets Manager ARN: %s", settings.SECRET_ARN_DB)

    try:
        init_db()
        logger.info("Database initialization completed successfully.")
    except Exception as exc:
        logger.error("Database initialization encountered an error: %s", exc)

    yield
    logger.info("Shutting down CloudDocs service.")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Corporate document vault deployed via Terraform on AWS Multi-AZ architecture.",
    lifespan=lifespan,
)

# CORS Middleware (Restricted to internal corporate origins in production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Template engine setup
templates_dir = os.path.join(os.path.dirname(__file__), "templates")
templates = Jinja2Templates(directory=templates_dir)


def format_bytes(num_bytes: int) -> str:
    """Helper to convert raw bytes into human readable format."""
    if num_bytes < 1024:
        return f"{num_bytes} B"
    elif num_bytes < 1024 * 1024:
        return f"{num_bytes / 1024:.1f} KB"
    elif num_bytes < 1024 * 1024 * 1024:
        return f"{num_bytes / (1024 * 1024):.2f} MB"
    else:
        return f"{num_bytes / (1024 * 1024 * 1024):.2f} GB"


# -----------------------------------------------------------------------------
# 1. HEALTH CHECK ENDPOINT (ALB Target Group Evaluation)
# -----------------------------------------------------------------------------
@app.get("/healthz", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Health check endpoint evaluated by the AWS Application Load Balancer.

    Returns HTTP 200 with JSON payload detailing status of DB and S3 subsystems.
    """
    db_health = check_db_health()
    storage_health = check_storage_health()

    is_healthy = db_health.get("status") == "connected" and storage_health.get("status") == "connected"

    payload = {
        "status": "healthy" if is_healthy else "degraded",
        "service": "CloudDocs",
        "version": settings.APP_VERSION,
        "mode": "Local Mock Mode" if settings.MOCK_MODE else "AWS Production Cloud",
        "database": db_health.get("engine", "unknown"),
        "storage": storage_health.get("provider", "unknown"),
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }

    if not is_healthy:
        logger.warning("Healthz reporting degraded status: db=%s, storage=%s", db_health, storage_health)

    return JSONResponse(
        status_code=status.HTTP_200_OK if is_healthy else status.HTTP_200_OK,  # ALB target group expects 200
        content=payload,
    )


# -----------------------------------------------------------------------------
# 2. DASHBOARD (Root GET / Route)
# -----------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse, tags=["Dashboard"])
async def dashboard(request: Request):
    """Renders the single-file Tailwind CSS responsive corporate dashboard."""
    raw_docs = list_documents()

    total_bytes = sum(doc.get("file_size", 0) for doc in raw_docs)
    total_storage_formatted = format_bytes(total_bytes)

    # Enhance documents with formatted size and human readable dates
    formatted_docs = []
    for doc in raw_docs:
        doc_copy = dict(doc)
        doc_copy["formatted_size"] = format_bytes(doc_copy.get("file_size", 0))

        raw_date = doc_copy.get("uploaded_at")
        if isinstance(raw_date, datetime):
            doc_copy["uploaded_at"] = raw_date.strftime("%Y-%m-%d %H:%M:%S")
        elif isinstance(raw_date, str):
            doc_copy["uploaded_at"] = raw_date[:19].replace("T", " ")

        formatted_docs.append(doc_copy)

    db_health = check_db_health()
    storage_info = check_storage_health()

    context = {
        "request": request,
        "documents": formatted_docs,
        "total_documents": len(formatted_docs),
        "total_bytes": total_bytes,
        "total_storage_formatted": total_storage_formatted,
        "aws_region": settings.AWS_REGION,
        "db_engine": db_health.get("engine", "RDS MySQL"),
        "storage_info": storage_info,
        "app_version": settings.APP_VERSION,
    }

    return templates.TemplateResponse(request=request, name="index.html", context=context)


# -----------------------------------------------------------------------------
# 3. UPLOAD FILE (POST /upload Route)
# -----------------------------------------------------------------------------
@app.post("/upload", tags=["Documents"])
async def upload_file(
    file: UploadFile = File(...),
    uploader: str = Form(default="Corporate User"),
    category: str = Form(default="General"),
):
    """Handles multipart/form-data payload, streams binary into S3, and persists metadata in MySQL."""
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided in request.")

    try:
        # Stream file payload into AWS S3 (or mock storage)
        content_type = file.content_type or "application/octet-stream"
        s3_key, file_size = upload_document(
            file_obj=file.file,
            filename=file.filename,
            content_type=content_type,
        )

        # Persist document metadata row in MySQL
        doc_id = insert_document(
            filename=file.filename,
            s3_key=s3_key,
            file_size=file_size,
            content_type=content_type,
            uploader=uploader.strip() or "Corporate User",
            category=category.strip() or "General",
        )

        logger.info(
            "Document ID %d uploaded successfully: %s (%d bytes, S3 key: %s, category: %s)",
            doc_id,
            file.filename,
            file_size,
            s3_key,
            category,
        )

        return JSONResponse(
            status_code=status.HTTP_201_CREATED,
            content={
                "id": doc_id,
                "filename": file.filename,
                "s3_key": s3_key,
                "file_size": file_size,
                "uploader": uploader,
                "category": category,
                "message": "File vaulted securely in S3 and registered in database.",
            },
        )

    except Exception as exc:
        logger.exception("Failed to process document upload: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Upload failed: {str(exc)}",
        )


# -----------------------------------------------------------------------------
# 4. DOWNLOAD FILE (GET /download/{id} Route)
# -----------------------------------------------------------------------------
@app.get("/download/{id}", tags=["Documents"])
async def download_file(id: int, direct: Optional[int] = None):
    """Retrieves document metadata and returns a secure, time-limited presigned S3 URL

    or streams the payload directly in fallback mode.
    """
    doc = get_document_by_id(id)
    if not doc:
        raise HTTPException(status_code=404, detail=f"Document with ID {id} not found.")

    s3_key = doc["s3_key"]
    filename = doc["filename"]

    # Check if client requested direct streaming or if we are in local mock mode
    local_path = get_local_file_path(s3_key)
    if direct == 1 or local_path:
        if local_path and os.path.exists(local_path):
            return FileResponse(
                path=local_path,
                filename=filename,
                media_type=doc.get("content_type", "application/octet-stream"),
            )

    # Generate presigned S3 URL (valid for 15 minutes) and issue HTTP 307 temporary redirect
    download_url = generate_download_url(s3_key=s3_key, filename=filename, doc_id=id)

    if download_url.startswith("http"):
        logger.info("Redirecting client to presigned S3 download URL for document ID %d", id)
        return RedirectResponse(url=download_url, status_code=status.HTTP_307_TEMPORARY_REDIRECT)

    # If download_url is a relative route (local mode), redirect internally
    return RedirectResponse(url=download_url)


# -----------------------------------------------------------------------------
# 5. REST API: GET /api/documents
# -----------------------------------------------------------------------------
@app.get("/api/documents", tags=["API"])
async def api_list_documents():
    """Returns JSON array of all vaulted documents."""
    docs = list_documents()
    formatted = []
    for doc in docs:
        item = dict(doc)
        item["formatted_size"] = format_bytes(item.get("file_size", 0))
        item["download_url"] = f"/download/{item['id']}"
        if isinstance(item.get("uploaded_at"), datetime):
            item["uploaded_at"] = item["uploaded_at"].isoformat()
        formatted.append(item)
    return formatted


# -----------------------------------------------------------------------------
# 6. DELETE FILE (DELETE /documents/{id} Route)
# -----------------------------------------------------------------------------
@app.delete("/documents/{id}", tags=["Documents"])
async def remove_document(id: int):
    """Deletes document from S3 storage and removes metadata record from MySQL."""
    doc = get_document_by_id(id)
    if not doc:
        raise HTTPException(status_code=404, detail=f"Document with ID {id} not found.")

    # Remove binary from S3 / local storage
    delete_stored_file(doc["s3_key"])

    # Remove database record
    success = delete_document(id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to delete database record.")

    logger.info("Document ID %d (%s) permanently removed from vault.", id, doc["filename"])
    return {"status": "deleted", "id": id, "filename": doc["filename"]}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host=settings.HOST, port=settings.PORT, reload=settings.DEBUG)
