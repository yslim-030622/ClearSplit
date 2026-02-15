# Backend (FastAPI)

ClearSplit backend is an async FastAPI service with SQLAlchemy 2.0 + Alembic on PostgreSQL.

## CI/CD Design

Pipeline stages are split by branch intent:

1. PR checks (fast feedback, required)
- `backend-lint`: syntax/undefined-name lint gate (`ruff` fatal rules only).
- `backend-migrations`: migration up/down/up validation on clean Postgres.
- `backend-test-pr`: non-e2e tests with coverage and JUnit output.

2. Main checks (release safety)
- `backend-test-main`: full suite including `e2e` smoke tests.
- `backend-archive-main`: backend Docker archive build verification.

Why this split:
- PR checks stay fast and actionable for review.
- `main` adds broader confidence and build artifact validation before release.

## Test Strategy

What is covered:
- Domain API suites: auth, groups, expenses, settlements, shopping.
- `e2e` smoke (`app/tests/test_backend_e2e.py`) validates one full cross-domain user journey.

Stability approach:
- Test DB isolation via per-test transaction rollback in `app/tests/conftest.py`.
- Receipt/S3 operations are stubbed in-memory (no real AWS dependency in tests).
- OCR in e2e is monkeypatched for deterministic output.

Removed low-value tests:
- `app/tests/test_models.py` (mostly schema/ORM construction checks duplicated by API flows).
- `app/tests/test_health.py` (outdated assertion incompatible with current health payload).

## Local Commands

From `backend/`:

```bash
# Install
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt

# Database migrations
alembic upgrade head

# PR-equivalent checks
make ci-pr

# Main-equivalent checks
make ci-main

# Full suite only (includes e2e)
make test-all

# Non-e2e suite only
make test-pr
```

Equivalent direct pytest commands:

```bash
pytest -m "not e2e" -v --durations=20
pytest -v --durations=30
```

Health endpoints:

- `GET /health/live`: process liveness probe.
- `GET /health/ready`: dependency readiness probe (returns `503` when degraded).
- `GET /health`: backward-compatible alias of readiness.

## Branching and PR Rules

1. Branch from `develop` or `main` with scoped name (for example: `backend/<topic>`).
2. Keep commits small and reviewable (tests + CI + docs separated when possible).
3. PR must pass:
- `Backend Lint`
- `Backend Migrations`
- `Backend Tests (PR)`
4. Merge to `main` requires full-suite and archive-build green.

## CI Secrets and Credentials

No real credentials are committed.

CI uses placeholders for test env values:
- `JWT_SECRET`
- `S3_BUCKET_NAME`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

For Azure staging deployment, GitHub Actions uses OIDC (no static Azure client secret). Configure:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `ACR_NAME`
- `ACR_LOGIN_SERVER`
- `ACA_APP_NAME`
- `ACA_MIGRATION_JOB`

Runtime app secrets should be stored in Azure Container Apps secrets (or Key Vault), not in workflow files.

## Troubleshooting CI Failures

1. Migration failure (`backend-migrations`)
- Reproduce locally:
  - `alembic upgrade head`
  - `alembic downgrade base`
  - `alembic upgrade head`
- Ensure new migrations are reversible.

2. Test failure (`backend-test-pr` / `backend-test-main`)
- Reproduce with same marker mode:
  - `pytest -m "not e2e" -v`
  - `pytest -v`
- Download and inspect CI artifacts:
  - `artifacts/pytest.log`
  - `artifacts/junit.xml`
  - `artifacts/coverage.xml`

3. Archive build failure (`backend-archive-main`)
- Reproduce locally:
  - `docker build -t clearsplit-backend:local ./backend`
