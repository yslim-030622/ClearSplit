# CI/CD Workflows

This directory contains GitHub Actions workflows for ClearSplit.

## Workflows

### `ci.yml` - Backend CI (PR + Main Gates)
Triggers:
- PR to `main`, `develop` for backend/workflow changes
- Push to `main` for backend/workflow changes
- Manual dispatch

Jobs:
- `Backend Lint` (PR + main): `ruff` fatal checks (`E9,F63,F7,F82`)
- `Backend Migrations` (PR + main): `alembic upgrade -> downgrade base -> upgrade`
- `Backend Tests (PR)` (PR only): `pytest -m "not e2e"` + coverage + junit
- `Backend Tests (Main Full Suite)` (main only): full `pytest` including `e2e`
- `Backend Archive Build (Main)` (main only): Docker archive build verification

Artifacts:
- `backend-pr-artifacts`: `pytest.log`, `junit.xml`, `coverage.xml`, `.coverage`
- `backend-main-test-artifacts`: full-suite test outputs + coverage
- `backend-main-build-artifacts`: Docker image inspect metadata

### `ios-pr-checks.yml` - iOS PR Quality Gates
Triggers:
- Pull requests targeting `main`, `develop` with iOS/workflow changes

Jobs:
- `lint` through `bundle exec fastlane ios lint`
- `build-and-unit` through `bundle exec fastlane ios build_ci` and `unit_tests_ci`

Artifacts:
- iOS logs and `.xcresult` from `ios/ClearSplit/.build`
- coverage summary in GitHub Step Summary

### `ios-main-checks.yml` - iOS Main Validation + Optional TestFlight
Triggers:
- Push to `main` with iOS/workflow changes
- Manual dispatch

Jobs:
- `full-validation`: lint + build + unit + UI smoke + unsigned archive
- `testflight` (manual/optional): TestFlight upload when secrets are present

### `docker.yml` - Docker Build & Push
Triggers:
- Push to `main`, tags `v*`, manual

### `security-scan.yml` - Security Scanning
Triggers:
- Push/PR to `main`, `develop`
- Weekly schedule

### `deploy-staging.yml` - Staging Deployment Template
Triggers:
- Push to `main`, manual

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

