# Repository Map

This map focuses on source-of-truth code and operational files, not local build caches.

## Top-Level Structure

| Path | Purpose | Notes |
| --- | --- | --- |
| `.github/workflows/` | CI/CD, security scans, Docker publish, deploy template | Multiple overlapping workflow files exist; `ci.yml` is the broadest pipeline. |
| `backend/` | API server, domain rules, persistence, tests | Core business logic and data model source of truth. |
| `ios/` | SwiftUI client app | Active code is in `ios/ClearSplit/Sources/ClearSplit/`. |
| `docs/` | Project documentation | Contains both current and legacy docs. |
| `scripts/` | Utility scripts | Security checks and S3 smoke testing helpers. |
| `web/` | Reserved web client area | Currently empty except for folder scaffolding. |
| `docker-compose.yml` | Local dev orchestration | Runs Postgres and API service. |
| `.env.example` | Environment template | Placeholder values only; copy to `.env`. |

## Backend Tree (`backend/`)

```text
backend/
  app/
    api/                 # FastAPI route handlers
    auth/                # JWT decode/encode + password + auth dependency
    core/                # settings and idempotency helpers
    db/                  # SQLAlchemy base/session setup
    models/              # SQLAlchemy domain models
    schemas/             # Pydantic request/response schemas
    services/            # business logic (group, expense, settlement, shopping, OCR)
    tests/               # API and model tests
    main.py              # FastAPI app entrypoint
  alembic/               # migration environment and version scripts
  db/schema.sql          # reference SQL snapshot (not canonical source)
  requirements.txt
  requirements-dev.txt
  Dockerfile
  Makefile
```

## iOS Tree (`ios/ClearSplit/`)

```text
ios/ClearSplit/
  Sources/ClearSplit/
    Config/              # API base URL resolution
    DesignSystem/        # colors and shared button styles
    Models/              # Codable models matching backend payloads
    Networking/          # API client and feature services
    State/               # global AppState orchestration
    Storage/             # Keychain token persistence
    Utilities/           # formatting helpers
    ViewModels/          # screen viewmodels
    Views/               # screens and reusable components
    RootView.swift       # auth-aware root navigation
  ClearSplit/
    ClearSplit.xcodeproj # Xcode project
    ClearSplit/          # minimal app-template residue
  Package.swift          # Swift package definition for ClearSplitCore
  Tests/                 # SwiftPM tests
```

## Docs Tree (`docs/`)

```text
docs/
  README.md
  INDEX.md
  project-overview.md
  repository-map.md
  file-tree-full.md
  dependencies.md
  backend-reference.md
  ios-reference.md
  workflows-and-operations.md
  architecture/
  adr/
  backend-docs/          # legacy references
  features/              # legacy references
  guides/                # legacy references
  security/              # legacy references
```

## Scripts and Ops Files

| Path | Functionality |
| --- | --- |
| `scripts/secret-scan.sh` | Regex-based tracked-file secret scanning helper. |
| `scripts/verify-security.sh` | Composite security posture check script. |
| `scripts/s3_smoke_test.py` | Verifies S3 write + presigned URL generation. |
| `backend/setup_db.sh` | Starts DB and runs migrations using local venv. |
| `backend/run_migration.sh` | Runs Alembic with provided/default `DATABASE_URL`. |
| `backend/test_api.sh` | End-to-end curl checks for API surface. |
| `backend/QUICK_TEST.sh` | Quick API sanity script (contains older signup assumptions). |

## Non-Source / Local Artifact Areas

These paths are present in the working tree but are not part of core implementation:

- `backend/.venv/`, `backend/venv/`, `.venv/`
- `backend/.pytest_cache/`
- `ios/ClearSplit/.build/`, `ios/ClearSplit/.swiftpm/`
- `tmp/DerivedData/`
- `__pycache__/` and `.pyc` artifacts
