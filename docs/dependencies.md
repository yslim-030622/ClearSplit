# Dependency Map

This document describes dependencies currently used by source code and operations.

## Backend Python Dependencies (`backend/requirements.txt`)

| Dependency | Why It Exists |
| --- | --- |
| `fastapi` | HTTP API framework and routing layer. |
| `uvicorn[standard]` | ASGI server for local/prod API process. |
| `sqlalchemy` | ORM and query layer for domain models. |
| `asyncpg` | Async PostgreSQL driver used by SQLAlchemy async engine. |
| `alembic` | Database schema migration tooling. |
| `pydantic` | Request/response validation and serialization. |
| `pydantic-settings` | Environment variable driven runtime settings. |
| `python-dotenv` | Loads `.env` values for local development. |
| `bcrypt` | Password hashing and verification. |
| `python-jose[cryptography]` | JWT encode/decode for access and refresh tokens. |
| `greenlet` | Required by SQLAlchemy async internals. |
| `boto3` | S3 client for receipt upload/download/delete and presigned URLs. |
| `pytesseract` | OCR bridge for receipt text extraction. |
| `Pillow` | Image processing before OCR. |
| `pytest`, `pytest-asyncio`, `httpx` | Tests and async API test client support. |

Notes:

- Test tooling is currently mixed into `requirements.txt` and not fully separated from runtime deps.
- OCR requires a system-level Tesseract installation in addition to Python packages.

## Backend Dev Dependencies (`backend/requirements-dev.txt`)

| Dependency | Use |
| --- | --- |
| `ruff` | Linting and formatting checks. |
| `mypy`, `types-python-jose` | Static type checking. |
| `pytest-cov`, `pytest-mock` | Test coverage and mocks. |
| `safety`, `pip-audit`, `bandit[toml]` | Dependency and code security scanning. |
| `black`, `isort` | Optional code-style alternatives/utilities. |

## iOS Dependencies

No third-party package dependency is declared in `ios/ClearSplit/Package.swift`.

The iOS client relies on Apple frameworks:

| Framework | Use |
| --- | --- |
| `SwiftUI` | Application UI and navigation. |
| `Foundation` | Date, JSON, URL, and core data types. |
| `Combine` | Observable state bindings in viewmodels/app state. |
| `Security` | Keychain token persistence. |
| `PhotosUI` | Photo library receipt picking. |
| `UIKit` | Camera capture and some receipt-review interaction glue. |

## Infrastructure Dependencies

| Dependency | Use |
| --- | --- |
| PostgreSQL 16 | Primary relational data store. |
| Docker / Docker Compose | Local database + API orchestration. |
| AWS S3 | Receipt object storage and download links. |
| Tesseract OCR (`tesseract-ocr`, `tesseract-ocr-eng`) | Receipt text extraction runtime. |

## CI/CD and Automation Dependencies

GitHub Actions workflows use:

- Python setup and pip caching for backend jobs.
- PostgreSQL service containers for integration tests.
- Xcode/macOS runners for iOS build/test jobs.
- TruffleHog, Bandit, Safety, pip-audit for security scanning.
- Docker Buildx + GHCR login/actions for image publishing.

## Coupling Notes

- Backend API response shapes drive iOS Codable models directly.
- Token lifecycle behavior is shared across backend JWT rules and iOS `APIClient` refresh logic.
- Shopping receipt flow couples S3 credentials, backend storage logic, OCR runtime, and iOS upload/review UX.
