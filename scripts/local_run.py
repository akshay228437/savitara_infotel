"""Convenience script to run CloudDocs locally in mock development mode."""

import os
import sys

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

os.environ["MOCK_MODE"] = "true"
os.environ["DEBUG"] = "true"

import uvicorn
from app.config import settings

if __name__ == "__main__":
    print("=" * 60)
    print(" Starting CloudDocs in Local Development Mode (SQLite & Mock S3)")
    print(f" URL: http://localhost:{settings.PORT}")
    print(f" Health Check: http://localhost:{settings.PORT}/healthz")
    print("=" * 60)
    uvicorn.run("app.main:app", host="127.0.0.1", port=settings.PORT, reload=True)
