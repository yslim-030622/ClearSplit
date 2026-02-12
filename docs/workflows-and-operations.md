# Workflows and Operations

## Local Development Workflow

### Backend

1. Create env file:

```bash
cp .env.example .env
```

2. Start database:

```bash
docker-compose up -d db
```

3. Install and migrate:

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
```

4. Run API:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

5. Run tests:

```bash
pytest
```

### iOS

Build through Xcode project:

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```

CLI build (project-based):

```bash
cd ios/ClearSplit
xcodebuild -project ClearSplit/ClearSplit.xcodeproj -scheme ClearSplit -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

SwiftPM test run:

```bash
swift test
```

## Helper Scripts

| Script | Purpose | Caveat |
| --- | --- | --- |
| `scripts/secret-scan.sh` | Scans tracked files for likely secret patterns. | Best used as a pre-commit signal, not a full DLP solution. |
| `scripts/verify-security.sh` | Runs a batch of security posture checks. | Some checks assume older config conventions and should be reviewed. |
| `scripts/s3_smoke_test.py` | Confirms S3 upload + presigned URL generation. | Requires valid AWS credentials and bucket config. |
| `backend/setup_db.sh` | Starts DB container and runs migrations. | Assumes local venv layout and specific container naming. |
| `backend/run_migration.sh` | Applies migrations using `DATABASE_URL`. | Good for explicit migration runs in local environments. |
| `backend/test_api.sh` | Curl-based API flow checks. | Contains assumptions aligned to earlier auth payloads. |
| `backend/QUICK_TEST.sh` | Quick sanity script. | Signup request shape is stale relative to current backend schema. |

## CI/CD Workflows (`.github/workflows/`)

| Workflow | What It Does |
| --- | --- |
| `ci.yml` | Main pipeline: backend lint/type/test/migrations + iOS build/test + summary. |
| `backend-ci.yml` | Focused backend test workflow for `main` PR/push. |
| `ios-ci.yml` | Focused SwiftPM iOS test workflow. |
| `security-scan.yml` | Secret scan, dependency scan, code security scan, summary. |
| `docker.yml` | Build/push backend image to GHCR and run image scan. |
| `deploy-staging.yml` | Staging deployment template with placeholder health-check/rollback notifications. |

## Runtime Dependencies Checklist

Before running end-to-end shopping and receipt flows, verify:

- PostgreSQL is reachable via `DATABASE_URL`
- JWT settings are configured
- S3 bucket and AWS credentials are valid
- Tesseract is available (for OCR paths)

## Operational Advice

- Treat Alembic migrations as the canonical schema source.
- Use idempotency headers for client-side retry safety on write endpoints.
- Keep scripts as convenience tooling; use tests and API contracts as source of truth when behavior differs.
