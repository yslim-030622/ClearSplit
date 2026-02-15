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
pip install -r requirements-dev.txt
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
| `ci.yml` | Backend lint, migration reversibility, PR/main test gates, and archive build on main. |
| `docker.yml` | Builds and pushes backend image to GHCR with Trivy scan. |
| `security-scan.yml` | Secret scan, dependency scan, and static security scan. |
| `deploy-staging.yml` | OIDC-based staging deployment to Azure Container Apps (runs after successful backend CI on `main`; ACR build/push, migration job, deploy, health verification, rollback-on-failure). |
| `ios-pr-checks.yml` | iOS PR lint/build/unit-test checks. |
| `ios-main-checks.yml` | iOS main-branch full validation and optional TestFlight flow. |

## Staging Deployment (Azure Container Apps + OIDC)

### Required GitHub Variables

Set these as repository variables or `staging` environment variables:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `ACR_LOGIN_SERVER`
- `ACA_APP_NAME`
- `ACA_MIGRATION_JOB`

### Required Azure Configuration

- GitHub federated credential for the deployment app registration.
- Deployment principal roles:
  - `AcrPush` on ACR.
  - `Container Apps Contributor` on the staging resource group.
- Container App runtime secrets configured in ACA or Key Vault:
  - `DATABASE_URL`
  - `JWT_SECRET`
  - `S3_BUCKET_NAME`
  - Optional static AWS keys only when not using identity-based auth.

### Deployment Flow

1. Build backend image and push to ACR.
2. Update and execute ACA migration job.
3. Update staging Container App image to new tag.
4. Verify `GET /health/live` and `GET /health/ready` return HTTP 200.
5. If health verification fails, roll back to the previously deployed image and fail the workflow.

## Runtime Dependencies Checklist

Before running end-to-end shopping and receipt flows, verify:

- PostgreSQL is reachable via `DATABASE_URL`
- `DATABASE_URL` includes TLS settings for managed PostgreSQL environments
- JWT settings are configured
- S3 bucket and credentials/identity are valid
- Tesseract is available (for OCR paths)

## Operational Advice

- Treat Alembic migrations as the canonical schema source.
- Use idempotency headers for client-side retry safety on write endpoints.
- Keep scripts as convenience tooling; use tests and API contracts as source of truth when behavior differs.
