# ClearSplit

ClearSplit is a group expense and shopping split platform with a FastAPI backend and a SwiftUI iOS client.  
The backend is the source of truth for auth, groups, expenses, settlements, shopping sessions, receipt storage, and OCR extraction.

## Repository At A Glance

- `backend/`: FastAPI app, SQLAlchemy models, Alembic migrations, tests.
- `ios/`: SwiftUI app (`ClearSplitCore`) with MVVM, API client, and Keychain token storage.
- `docs/`: project documentation index, architecture notes, dependency map, and implementation references.
- `.github/workflows/`: CI, security scanning, Docker build, staging deploy template.
- `scripts/`: local helper scripts for security checks and S3 smoke testing.

## Core Capabilities

- JWT authentication (signup, login, refresh, me).
- Group and membership management (owner/member roles).
- Expense creation with equal split calculation and idempotency.
- Settlement batch computation and debtor-only settlement status updates.
- Shopping sessions with participants, receipt uploads, item-level splits.
- OCR extraction pipeline for receipts backed by S3 and Tesseract.

## Quick Start

### 1. Configure environment

```bash
cp .env.example .env
```

Set at least:
- `DATABASE_URL`
- `JWT_SECRET`
- `S3_BUCKET_NAME`
- `AWS_REGION`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### 2. Start PostgreSQL

```bash
docker-compose up -d db
```

### 3. Start backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health check:

```bash
curl http://127.0.0.1:8000/health
```

### 4. Run iOS app

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```

Or CLI build:

```bash
cd ios/ClearSplit
xcodebuild -project ClearSplit/ClearSplit.xcodeproj -scheme ClearSplit -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Testing

Backend:

```bash
cd backend
pytest
```

iOS SwiftPM tests:

```bash
cd ios/ClearSplit
swift test
```

## Documentation

Start here:

- `docs/INDEX.md`
- `docs/project-overview.md`
- `docs/repository-map.md`
- `docs/file-tree-full.md`
- `docs/dependencies.md`
- `docs/backend-reference.md`
- `docs/ios-reference.md`
- `docs/workflows-and-operations.md`
