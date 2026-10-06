"""Automated Integration & Unit Tests for CloudDocs Application.

Tests:
1. Health check (/healthz) returns 200 with JSON payload
2. Dashboard (/) serves responsive HTML page
3. File upload (/upload) streams multipart payload and registers DB row
4. File download (/download/{id}) retrieves vaulted file
5. API listing (/api/documents) returns valid JSON array
6. File deletion (/documents/{id}) successfully purges object
"""

import io
import os
import pytest
from fastapi.testclient import TestClient

# Force Mock Mode for testing suite
os.environ["MOCK_MODE"] = "true"
os.environ["APP_ENV"] = "testing"

from app.main import app
from app.db import init_db

client = TestClient(app)


@pytest.fixture(autouse=True)
def setup_database():
    """Ensure database tables exist before running test scenarios."""
    init_db()


def test_healthz_endpoint():
    """Verify ALB target group health check endpoint returns 200 OK."""
    response = client.get("/healthz")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("healthy", "degraded")
    assert data["service"] == "CloudDocs"
    assert "database" in data
    assert "storage" in data


def test_dashboard_root_endpoint():
    """Verify root GET / renders HTML dashboard."""
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "CloudDocs" in response.text
    assert "Enterprise Vault" in response.text


def test_document_lifecycle():
    """Verify full document lifecycle: Upload -> List -> Download -> Delete."""
    # 1. Upload a test document
    test_content = b"CloudDocs Confidential Architecture Blueprint 2026."
    test_filename = "architecture_spec.pdf"
    
    files = {
        "file": (test_filename, io.BytesIO(test_content), "application/pdf")
    }
    data = {
        "uploader": "Security Engineer",
        "category": "Engineering"
    }

    upload_resp = client.post("/upload", files=files, data=data)
    assert upload_resp.status_code == 201
    upload_data = upload_resp.json()
    assert upload_data["filename"] == test_filename
    assert upload_data["file_size"] == len(test_content)
    assert upload_data["uploader"] == "Security Engineer"
    doc_id = upload_data["id"]

    # 2. Check document appears in API listing
    api_resp = client.get("/api/documents")
    assert api_resp.status_code == 200
    docs = api_resp.json()
    matching = [d for d in docs if d["id"] == doc_id]
    assert len(matching) == 1
    assert matching[0]["filename"] == test_filename

    # 3. Download the document
    dl_resp = client.get(f"/download/{doc_id}?direct=1")
    assert dl_resp.status_code in (200, 307)
    if dl_resp.status_code == 200:
        assert dl_resp.content == test_content

    # 4. Delete the document
    del_resp = client.delete(f"/documents/{doc_id}")
    assert del_resp.status_code == 200
    assert del_resp.json()["status"] == "deleted"

    # 5. Confirm deletion
    get_deleted = client.get(f"/download/{doc_id}")
    assert get_deleted.status_code == 404
