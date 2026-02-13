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
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head

# PR-equivalent checks
make ci-pr

# Main-equivalent checks (includes e2e)
make ci-main

# Full backend suite directly
pytest -v
```

iOS (Fastlane + scripts):

```bash
cd ios/ClearSplit
bundle install

# PR-equivalent checks
bundle exec fastlane ios ci_pr

# Full validation (main-equivalent)
bundle exec fastlane ios ci_main
```

You can also run the underlying scripts directly:

```bash
cd ios/ClearSplit
./scripts/ios_lint.sh
./scripts/ios_build.sh
./scripts/ios_test.sh unit
./scripts/ios_test.sh ui
./scripts/ios_archive.sh
```

## Backend CI/CD Design

Pipeline architecture (GitHub Actions):
- Stage 1 (PR): lint (`ruff` fatal rules), migration validation, non-e2e tests with coverage and JUnit artifacts.
- Stage 2 (main): full backend suite (includes `e2e` smoke), then Docker archive build validation.

Why these stages exist:
- PR checks stay fast and focused on actionable failures.
- Main checks validate full backend behavior and deployability.

Artifacts and debugging outputs:
- Backend workflows upload `pytest.log`, `junit.xml`, `coverage.xml`, and `.coverage`.
- Main build uploads Docker image inspection metadata for traceability.

## iOS CI/CD Design

Pipeline architecture (GitHub Actions + Fastlane):
- Stage 1: PR quality gates (`.github/workflows/ios-pr-checks.yml`) run lint, simulator build, and unit tests to keep feedback fast.
- Stage 2: Main branch validation (`.github/workflows/ios-main-checks.yml`) runs lint, build, unit tests, UI smoke tests, and unsigned archive validation.
- Stage 3: Optional release delivery (`workflow_dispatch` + `deploy_testflight=true`) runs the TestFlight lane when App Store Connect and signing secrets are configured.

Why these stages exist:
- PR checks are optimized for speed and signal-to-noise during code review.
- Main checks add slower release-safety gates (UI tests + archive).
- TestFlight is separated so release credentials are only used intentionally.

Artifacts and debugging outputs:
- iOS workflows upload `.xcresult` bundles and build logs from `ios/ClearSplit/.build`.
- Unit test coverage summary is attached to GitHub job summaries.

See `ios/README.md` for detailed local workflow, branch/PR rules, secrets, and troubleshooting.

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
