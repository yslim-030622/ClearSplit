# CI/CD Workflows

This directory contains GitHub Actions workflows for ClearSplit.

## Workflows

### `ci.yml` - Backend CI (PR + Main Gates)
Triggers:
- PR to `main`, `develop` for backend/workflow changes
- Push to `main` for backend/workflow changes
- Manual dispatch

Jobs:
- `Backend Lint` (PR + main): `ruff check app app/tests`
- `Backend Migrations` (PR + main): `alembic upgrade -> downgrade base -> upgrade`
- `Backend Tests (PR)` (PR only): `pytest -m "not e2e"` + JUnit + coverage (fail-under 78%)
- `Backend Tests (Main Full Suite)` (main only): full `pytest` including `e2e` (fail-under 80%)
- `Backend Archive Build (Main)` (main only): Docker archive build verification

### `docker.yml` - Docker Build & Push to GHCR
Triggers:
- Push to `main`
- Tags `v*`
- Manual dispatch

### `security-scan.yml` - Security Scanning
Triggers:
- Push/PR to `main`, `develop`
- Weekly schedule

### `deploy-staging.yml` - Azure Container Apps Staging Deployment (OIDC)
Triggers:
- `Backend CI` workflow completed successfully on `main` (`workflow_run`)
- Manual dispatch

Jobs:
- Build and push backend image to ACR
- Trigger ACA migration job (`python -m alembic upgrade head`) and wait for completion
- Deploy new ACA revision
- Verify `/health/live` and `/health/ready`
- Roll back to previous image automatically if health verification fails

Required repository or environment variables:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `ACR_LOGIN_SERVER`
- `ACA_APP_NAME`
- `ACA_MIGRATION_JOB`

Required permissions:
- `id-token: write` for OIDC
- `contents: read`

Notes:
- No `AZURE_CREDENTIALS` secret is required.
- Runtime secrets (for app config) should be managed in Azure Container Apps secrets or Key Vault.

### `ios-pr-checks.yml` - iOS PR Quality Gates
Triggers:
- Pull requests targeting `main`, `develop` with iOS/workflow changes

### `ios-main-checks.yml` - iOS Main Validation + Optional TestFlight
Triggers:
- Push to `main` with iOS/workflow changes
- Manual dispatch

## Local Equivalents

Backend:

```bash
cd backend
make ci-pr    # PR-equivalent
make ci-main  # Main-equivalent
```

iOS:

```bash
cd ios/ClearSplit
bundle exec fastlane ios ci_pr
bundle exec fastlane ios ci_main
```

## Required Checks Recommendation

For backend PR protection:
- `Backend Lint`
- `Backend Migrations`
- `Backend Tests (PR)`

For `main` push confidence:
- `Backend Tests (Main Full Suite)`
- `Backend Archive Build (Main)`
