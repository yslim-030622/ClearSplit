# Dependencies

## Backend Runtime

Defined in `backend/requirements.txt`.

Core platform:
- `fastapi`, `uvicorn[standard]`
- `sqlalchemy`, `asyncpg`, `alembic`
- `pydantic`, `pydantic-settings`, `email-validator`

Auth and security:
- `bcrypt`
- `PyJWT[crypto]`
- `cryptography`

Storage and files:
- `boto3`
- `python-multipart`

OCR:
- `pytesseract`
- `Pillow`

Compatibility and packaging guardrails:
- `starlette`
- `greenlet`
- `jaraco.context`
- `wheel`

## Backend Development

Defined in `backend/requirements-dev.txt`.

Test and quality:
- `pytest`, `pytest-asyncio`, `pytest-cov`, `pytest-mock`, `httpx`
- `ruff`, `mypy`
- `black`, `isort` (optional style tooling)

Security tooling:
- `safety`
- `pip-audit`
- `bandit[toml]`

## iOS Dependencies

Swift package:
- local package target `ClearSplitCore` (no third-party SPM dependencies currently declared)

Ruby tooling:
- `fastlane` via `ios/ClearSplit/Gemfile`

Apple frameworks used heavily:
- SwiftUI
- Foundation
- Combine
- URLSession

## System-Level Requirements

Backend runtime environment expects:
- Python 3.11+
- PostgreSQL
- Tesseract OCR + English language data

Containerized backend (`backend/Dockerfile`) installs:
- `tesseract-ocr`
- `tesseract-ocr-eng`

## Versioning Notes

- Critical runtime libraries are pinned or constrained to avoid incompatible upgrades.
- Security/packaging libraries are explicitly constrained in requirements where needed for CI gates.
