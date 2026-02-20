# Workflows and Operations

## Local Development

### Backend Setup (without Docker)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
make run
```

The server starts at `http://localhost:8000` with auto-reload enabled.

### Backend with Docker Compose

From repo root:

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env with your settings

docker compose up --build
```

This starts:
- **PostgreSQL 16** on `localhost:${POSTGRES_PORT:-5432}`
- **FastAPI API** on `http://localhost:8000` with live reload and volume mount

To route local API requests to an external PostgreSQL (for example AWS RDS),
export `API_DATABASE_URL` before starting compose:

```bash
export API_DATABASE_URL='postgresql+asyncpg://<user>:<password>@<rds-host>:5432/<db>?ssl=require'
docker compose up --build
```

In this mode, the iOS simulator still targets local API (`127.0.0.1:8000`),
while the backend writes to the external database.

### iOS Setup

```bash
# Open Xcode project
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj

# Install Fastlane dependencies (optional, for CI lanes)
cd ios/ClearSplit
bundle install
```

- **Simulator**: uses `http://127.0.0.1:8000` by default
- **Physical device**: set `API_BASE_URL` in Xcode scheme -> Run -> Arguments -> Environment Variables
- **Staging backend**: the shared scheme may have a staging URL configured — remove it to use local

API base URL resolution order:
1. Xcode scheme environment variable `API_BASE_URL`
2. Info.plist `API_BASE_URL` key
3. Default: `http://127.0.0.1:8000`

## Daily Engineering Loops

### Add a Backend Endpoint

1. Add or update schema in `backend/app/schemas/`
2. Add route in `backend/app/api/`
3. Implement business rule in `backend/app/services/`
4. Add or adjust tests in `backend/app/tests/`
5. Run `make ci-pr` to validate

### Change Persistence Model

1. Update model in `backend/app/models/`
2. Generate migration: `alembic revision --autogenerate -m "description"`
3. Verify migration file in `backend/alembic/versions/`
4. Run `alembic upgrade head`
5. Run tests to validate

### iOS Feature Addition

1. Add or update model in `Models/`
2. Add networking call in `Networking/` (implement service protocol)
3. Wire orchestration in `State/AppState.swift` and/or new ViewModel
4. Build UI in `Views/`
5. Validate with `./scripts/ios_test.sh all`

## Testing and Quality

### Backend Commands

```bash
cd backend

# Linting
make lint-ci                # Ruff syntax and style checks

# Testing
make test                   # Full test suite
make test-pr                # PR gate: no e2e, 78% coverage minimum
make test-all               # Staging gate: with e2e, 80% coverage minimum

# Combined gates
make ci-pr                  # Lint + PR tests
make ci-main                # Lint + staging tests

# Direct pytest
pytest -m "not e2e" -v --durations=20     # PR equivalent
pytest -v --durations=30                   # Full suite
```

**Test coverage**: 143+ tests across 13 files:
- `test_shopping.py` — 51 tests (session lifecycle, items, sharers, receipts)
- `test_groups.py` — 31 tests (CRUD, membership, roles)
- `test_expenses.py` — 26 tests (creation, splits, balances)
- `test_auth.py` — 24 tests (signup, login, tokens, credentials)
- `test_friends.py` — 21 tests (requests, accept/decline, removal)
- `test_settlements.py` — 19 tests (computation, payments, confirmation)
- `test_security.py` — 19 tests (headers, CORS, token tampering, timing attacks)
- `test_rate_limit.py` — 6 tests (limiter behavior, proxy headers)
- `test_connect_args.py` — 4 tests (TLS connection parameters)
- `test_refresh_tokens.py` — 4 tests (rotation, replay, revocation)
- `test_ocr.py` — 1 test (Tesseract processing)
- `test_backend_e2e.py` — 1 test (full cross-domain user journey)

**Test isolation**: Each test runs in its own database transaction that rolls back after completion. Receipt/S3 operations are stubbed in-memory.

### iOS Commands

```bash
cd ios/ClearSplit

# Scripts
./scripts/ios_build.sh            # Simulator build
./scripts/ios_test.sh unit        # Unit tests
./scripts/ios_test.sh ui          # UI smoke tests
./scripts/ios_test.sh all         # Full suite
./scripts/ios_lint.sh             # SwiftLint
./scripts/ios_archive.sh          # Unsigned release archive

# Fastlane lanes
bundle exec fastlane ios lint
bundle exec fastlane ios build
bundle exec fastlane ios test_unit
bundle exec fastlane ios test_ui
bundle exec fastlane ios test_all
bundle exec fastlane ios archive
bundle exec fastlane ios ci_pr       # PR gate: lint + build + unit tests
bundle exec fastlane ios ci_main     # Main gate: lint + build + all tests + archive
```

Scripts auto-select an available iPhone simulator. Override with `IOS_DESTINATION` or `IOS_SIMULATOR_NAME`.

## Migrations

### Apply Latest Migrations

```bash
cd backend
alembic upgrade head
```

### Validate Migration Reversibility

```bash
alembic upgrade head
alembic downgrade base
alembic upgrade head
```

This is what CI does on every PR to catch irreversible migrations.

### Generate New Migration

```bash
alembic revision --autogenerate -m "description of change"
```

### Migration Precheck

For deployments with existing data, run the precheck script:

```bash
python backend/app/scripts/migration_precheck.py
```

This checks for case-insensitive duplicate emails/usernames before related constraints are enforced.

## CI/CD Pipelines

### Backend CI (`ci.yml`)

**Triggers**: PRs to main/develop, push to staging, manual dispatch

| Job | Gate | What it does |
|-----|------|-------------|
| Backend Lint | PR + Staging | `ruff check app app/tests` |
| Backend Migrations | PR + Staging | `alembic upgrade -> downgrade base -> upgrade` on clean PostgreSQL 16 |
| Backend Tests (PR) | PR only | `pytest -m "not e2e"` with 78% coverage minimum |
| Backend Tests (Staging) | Staging push | Full `pytest` including e2e with 80% coverage minimum |
| Backend Archive Build | Staging push | Docker image build verification |

### Docker Build (`docker.yml`)

**Triggers**: Push to main, `v*` tags, manual dispatch

- Builds Docker image with Buildx (linux/amd64)
- Tags: branch, semver, commit SHA, latest
- Pushes to GitHub Container Registry (GHCR)
- Trivy scan for HIGH/CRITICAL vulnerabilities (fails build if found)

### iOS PR Checks (`ios-pr-checks.yml`)

**Triggers**: PRs to main/develop with iOS changes

- SwiftLint validation
- Simulator build
- Unit test execution with coverage summary

### iOS Main Checks (`ios-main-checks.yml`)

**Triggers**: Push to main, manual dispatch

- Full validation: lint + build + all tests + unsigned archive
- Optional TestFlight upload via `deploy_testflight` input flag
- Requires App Store Connect API credentials (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT)

### Security Scan (`security-scan.yml`)

**Triggers**: PRs, push to main/develop, weekly schedule (Sunday 00:00)

| Job | Tool | Purpose |
|-----|------|---------|
| Secret Scanning | TruffleHog | Verified secrets in git history |
| Dependency Scan | pip-audit | CVE detection in Python dependencies |
| Code Security | Bandit | Python code security patterns |
| Summary | — | Aggregated results published to GitHub |

### Staging Deployment (`deploy-staging.yml`)

**Triggers**: Backend CI success on staging push, manual dispatch

**Authentication**: Azure OIDC (no static credentials)

**Steps**:
1. **Build & Push**: Docker image to Azure Container Registry (ACR) with Trivy scan
2. **Migrate**: ACA migration container job runs precheck + `alembic upgrade head`
3. **Deploy**: New ACA revision with health check verification
4. **Verify**: `/health/live` and `/health/ready` endpoint checks
5. **Rollback**: Automatic revert to previous image if health checks fail

**Required configuration**:
- Azure: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`
- Container: `ACR_NAME`, `ACR_LOGIN_SERVER`, `ACA_APP_NAME`, `ACA_MIGRATION_JOB`
- App secrets: `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`, `S3_BUCKET_NAME`

### Local CI Equivalents

```bash
# Backend
cd backend
make ci-pr       # Matches PR gate
make ci-main     # Matches staging gate

# iOS
cd ios/ClearSplit
bundle exec fastlane ios ci_pr       # Matches PR gate
bundle exec fastlane ios ci_main     # Matches main gate
```

## Operational Scripts

### Security Scans

```bash
# Scan for hardcoded secrets (JWT, passwords, API keys, AWS keys, private keys)
./scripts/secret-scan.sh

# Verify security baseline (gitignore, env files, SecretStr types, secret-scan.sh)
./scripts/verify-security.sh
```

### Pre-commit Hooks

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

Hooks:
- Trailing whitespace and end-of-file fixer
- Merge conflict detection
- Large file detection
- Ruff Python linting (`backend/app/**/*.py`)
- Custom secret scanner

### S3 Integration Smoke Test

```bash
python scripts/s3_smoke_test.py
```

Requires S3-related environment variables (`S3_BUCKET_NAME`, AWS credentials).

## Troubleshooting

### API is Up but App Cannot Connect

- Confirm backend is listening on `0.0.0.0` when testing from device
- Set `API_BASE_URL` to host LAN IP for physical devices
- Verify that `/health/live` responds from the same network path
- Check if Xcode scheme has staging URL that overrides local

### Receipt Upload Failures

- Verify `S3_BUCKET_NAME` and AWS credentials/permissions
- Verify file format is one of JPEG/PNG/WEBP/GIF
- Verify image is below configured byte (10 MB) and pixel (25M) limits
- Check `content_type` header in upload request

### OCR Timeout or No Extracted Items

- Use a clearer receipt image with higher text contrast
- Check backend logs for OCR timeout or image validation errors
- Verify Tesseract is installed in runtime environment (`tesseract --version`)
- Check `MAX_OCR_CONCURRENCY` setting if requests are queuing

### Migration Failures

Reproduce locally:
```bash
alembic upgrade head
alembic downgrade base
alembic upgrade head
```
Ensure new migrations are reversible. Check CI artifacts for `pytest.log` and `junit.xml`.

### iOS CI Failures

- `Unable to find destination`: Override simulator with `IOS_SIMULATOR_NAME='iPhone 17' ./scripts/ios_test.sh unit`
- `SwiftLint not found`: Install with `brew install swiftlint`
- `Bundler/Fastlane errors`: Refresh gems with `bundle install`
- `UI tests flaky`: Close Simulator and rerun; keep `UITEST_MODE` launch argument enabled
