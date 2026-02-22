# CI/CD Workflows

This directory contains GitHub Actions workflows for ClearSplit.

## Workflows

### `ci.yml` - Backend CI (Main-Branch Release Gate)
Triggers:
- PR to `main` for backend/workflow changes
- Push to `main` for backend/workflow changes
- Manual dispatch

Jobs:
- `Backend Lint`: `ruff check app app/tests`
- `Backend Migrations`: `alembic upgrade head` + migration precheck (forward-only policy)
- `Backend Tests (PR)`: `pytest -m "not e2e"` with 80% coverage gate
- `Backend Tests (Main Full Suite)`: full `pytest` (includes `e2e`) with 80% coverage gate

### `deploy-aca-reusable.yml` - Shared ACA Deployment Logic (`workflow_call`)
Inputs:
- `target_environment`: `staging` or `production`
- `deploy_mode`: `build` or `promote`
- `source_sha`: commit SHA to deploy
- `image_digest` (optional)
- `staging_run_id` (optional)
- `build_run_id` (optional)

What it does:
- Validates environment/runtime configuration
- Resolves deploy image:
  - `build`: builds and pushes to ACR
  - `promote`: reuses existing ACR image digest (no rebuild)
  - If production ACR is separate, it can import from staging ACR when `STAGING_ACR_NAME` and `STAGING_ACR_LOGIN_SERVER` are set in production environment vars
- Runs migration precheck + `alembic upgrade head` via ACA job
- Deploys new ACA revision
- Verifies `/health/live` and `/health/ready`
- Rolls back to previous image if health verification fails
- Publishes deployment summary

### `deploy-staging.yml` - Staging Wrapper
Triggers:
- `Backend CI` completed successfully on `main` push (`workflow_run`)
- Manual dispatch (main only)

Gates:
- Validates source SHA
- Requires successful `ci.yml` push run for the same SHA

Mode:
- Calls reusable workflow with `target_environment=staging`, `deploy_mode=build`

### `deploy-production.yml` - Production Wrapper
Triggers:
- Manual dispatch only

Inputs:
- `source_sha` (required)
- `confirm_production` (must be `YES`)

Gates:
- Main branch only
- Requires successful `ci.yml` push run for `source_sha`
- Requires successful `deploy-staging.yml` run for `source_sha`

Mode:
- Calls reusable workflow with `target_environment=production`, `deploy_mode=promote`
- Reuses immutable staging run-tagged image digest

### `security-scan.yml` - Security Scanning
Triggers:
- Push/PR to `main`, `develop`
- Weekly schedule

### `ios-pr-checks.yml` - iOS PR Quality Gates
Triggers:
- Pull requests targeting `main`, `develop` with iOS/workflow changes

### `ios-main-checks.yml` - iOS Main Validation + Optional TestFlight
Triggers:
- Push to `main` with iOS/workflow changes
- Manual dispatch

## Deployment Image Source of Truth

Runtime deployments use **Azure Container Registry (ACR)** only.

- Staging builds image once and records immutable run-stamped tag.
- Production promotes that validated image digest without rebuilding.

## GitHub Environment Variables Checklist

Set these GitHub Environment variables for each deployment target.

Common required variables (staging and production):
- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `ACR_LOGIN_SERVER`
- `ACA_APP_NAME`
- `ACA_MIGRATION_JOB`
- `CORS_ORIGINS`
- `S3_BUCKET_NAME`

Staging environment:
- `AZURE_RESOURCE_GROUP`: staging resource group
- `ACR_NAME`: staging ACR name
- `ACR_LOGIN_SERVER`: staging ACR login server
- `ACA_APP_NAME`: staging Container App
- `ACA_MIGRATION_JOB`: staging migration job
- `S3_BUCKET_NAME`: staging bucket

Production environment:
- `AZURE_RESOURCE_GROUP`: production resource group
- `ACR_NAME`: production ACR name
- `ACR_LOGIN_SERVER`: production ACR login server
- `ACA_APP_NAME`: production Container App
- `ACA_MIGRATION_JOB`: production migration job
- `S3_BUCKET_NAME`: production bucket
- `STAGING_ACR_NAME`: staging ACR name (for cross-ACR import fallback)
- `STAGING_ACR_LOGIN_SERVER`: staging ACR login server (for cross-ACR import fallback)

Notes:
- In production, `ACR_NAME` and `ACR_LOGIN_SERVER` must reference the production registry, not staging.
- `STAGING_ACR_NAME` and `STAGING_ACR_LOGIN_SERVER` are required only when staging and production use separate ACRs. They are optional for shared-ACR setups.

## Required Checks Recommendation

For backend PR protection:
- `Backend Lint`
- `Backend Migrations`
- `Backend Tests (PR)`

For release safety (`main` push):
- `Backend Tests (Main Full Suite)`
- `Deploy to ACA Staging`

For production release:
- `Deploy to ACA Production` (manual + environment approvals)
