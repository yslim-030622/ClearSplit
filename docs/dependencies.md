# Dependencies

## Backend Runtime

Defined in `backend/requirements.txt` (23 packages).

### Core Platform

| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | 0.122.0 | Web framework |
| `uvicorn[standard]` | 0.30.1 | ASGI server |
| `starlette` | >= 0.49.1 | ASGI toolkit (FastAPI dependency) |
| `sqlalchemy` | >= 2.0.30 | Async ORM |
| `asyncpg` | >= 0.29.0 | PostgreSQL async driver |
| `alembic` | 1.13.1 | Database migrations |
| `pydantic` | 2.8.2 | Data validation and schemas |
| `pydantic-settings` | 2.3.3 | Settings management |
| `email-validator` | >= 2.2.0 | Email format validation |
| `python-dotenv` | 1.0.1 | Environment file loading |
| `python-multipart` | >= 0.0.20 | Multipart form parsing (file uploads) |

### Auth and Security

| Package | Version | Purpose |
|---------|---------|---------|
| `bcrypt` | 4.1.2 | Password hashing |
| `PyJWT[crypto]` | >= 2.10.1, < 3.0.0 | JWT token creation and validation |
| `cryptography` | >= 46.0.5 | Underlying cryptographic primitives |

### Storage and OCR

| Package | Version | Purpose |
|---------|---------|---------|
| `boto3` | >= 1.34.0 | AWS S3 client for receipt storage |
| `pytesseract` | 0.3.10 | Tesseract OCR Python wrapper |
| `Pillow` | >= 12.1.1 | Image processing and validation |

### Compatibility

| Package | Version | Purpose |
|---------|---------|---------|
| `greenlet` | >= 3.0.0 | SQLAlchemy async support |
| `jaraco.context` | >= 6.1.0 | Packaging guardrail |
| `wheel` | >= 0.46.2 | Packaging guardrail |

## Backend Development

Defined in `backend/requirements-dev.txt` (includes all production dependencies).

### Testing

| Package | Version | Purpose |
|---------|---------|---------|
| `pytest` | 8.3.2 | Test runner |
| `pytest-asyncio` | 0.25.2 | Async test support |
| `pytest-cov` | 4.1.0 | Coverage reporting |
| `pytest-mock` | 3.12.0 | Mocking and monkeypatching |
| `httpx` | 0.27.0 | Async HTTP test client |

### Linting and Type Checking

| Package | Version | Purpose |
|---------|---------|---------|
| `ruff` | 0.1.15 | Python linter (replaces flake8/isort) |
| `mypy` | 1.8.0 | Static type checking |
| `black` | 24.3.0 | Code formatter (optional) |
| `isort` | 5.13.2 | Import sorting (optional) |

### Security Scanning

| Package | Version | Purpose |
|---------|---------|---------|
| `safety` | >= 3.7.0 | Dependency vulnerability scanning |
| `pip-audit` | 2.6.2 | CVE detection in Python packages |
| `bandit[toml]` | 1.7.6 | Python code security analysis |

## iOS Dependencies

### Swift Packages

**Zero external SPM dependencies.** The iOS app is built entirely on Apple frameworks:

| Framework | Usage |
|-----------|-------|
| SwiftUI | Declarative UI framework |
| Foundation | Base library, networking, JSON |
| Combine | Reactive programming patterns |
| Security | Keychain Services for token storage |
| UIKit | Limited use (haptic feedback only) |

### Build Tool Dependencies

| Tool | Version | Source | Purpose |
|------|---------|--------|---------|
| `fastlane` | >= 2.222.0 | Gemfile (Ruby) | Build automation and deployment |
| SwiftLint | Latest | Homebrew | Swift code linting |
| Xcode | 15+ | App Store | Build system and IDE |

## System-Level Requirements

### Backend Runtime

| Dependency | Minimum Version | Notes |
|-----------|-----------------|-------|
| Python | 3.11+ | Specified in `.python-version` |
| PostgreSQL | 16 | Used in Docker Compose and CI |
| Tesseract OCR | Latest | With English language data |

### Containerized Backend (`backend/Dockerfile`)

Base image: `python:3.11-slim`

System packages installed:
- `tesseract-ocr` — OCR engine
- `tesseract-ocr-eng` — English language data

### iOS Development

| Dependency | Minimum Version | Notes |
|-----------|-----------------|-------|
| Xcode | 15+ | Required for SwiftUI and Swift 5.9+ |
| iOS deployment target | 16.0 | Set in `Package.swift` |
| macOS deployment target | 12.0 | For macOS Catalyst support |
| Ruby | 3.2+ | For Fastlane CI lanes |

## CI/CD Tool Dependencies

| Tool | Version | Used In | Purpose |
|------|---------|---------|---------|
| Docker | Latest | `docker.yml`, `deploy-staging.yml` | Container builds |
| Docker Buildx | Latest | `docker.yml` | Multi-platform builds |
| Trivy | Latest | `docker.yml`, `deploy-staging.yml` | Container vulnerability scanning |
| TruffleHog | Latest | `security-scan.yml` | Secret detection in git history |
| Azure CLI | Latest | `deploy-staging.yml` | Azure Container Apps deployment |
| GitHub CLI | Latest | Various workflows | GitHub Actions integration |

## Versioning Notes

- Critical runtime libraries are pinned or constrained to avoid incompatible upgrades
- Security and packaging libraries are explicitly constrained in requirements where needed for CI gates
- `PyJWT` is upper-bounded at `< 3.0.0` to prevent breaking API changes
- `cryptography` is lower-bounded at `>= 46.0.5` for security patches
