# System Architecture Overview
ClearSplit backend is an async FastAPI service that provides authentication, friend relationships, group membership, expense splitting, settlement computation/payment tracking, shopping-session itemization, receipt storage, and receipt OCR extraction. This is evidenced by route/service modules in `backend/app/api/*.py`, `backend/app/services/*.py`, and the repository description in `README.md`.

Architectural style: modular monolith.
- API layer: FastAPI routers in `backend/app/api/`.
- Domain/service layer: business logic in `backend/app/services/`.
- Data layer: SQLAlchemy ORM models in `backend/app/models/` + Alembic migrations in `backend/alembic/versions/`.
- Cross-cutting auth/config/core: `backend/app/auth/` and `backend/app/core/`.
- External integrations: PostgreSQL, S3 (`boto3`), OCR (`pytesseract`/Tesseract).

How to think about this repo: treat `backend/` as one deployable API process with clear domain folders, but not strict clean-architecture enforcement. The shape is understandable and practical, yet some request handlers still mix orchestration, authorization checks, and direct ORM access, so deployment hardening should prioritize boundary cleanup, operational guardrails, and runtime safety.

Backend deployment goal statement: deploy a repeatable, secure, observable backend release pipeline where `backend/app/main.py` runs reliably against migrated PostgreSQL, with secrets injected by environment/secret manager (not local files), and with health/readiness gates that reflect real dependency status.

# Repository Structure
Condensed tree (deployment-relevant):
```text
.
├── .github/workflows/
│   ├── ci.yml
│   ├── docker.yml
│   ├── deploy-staging.yml
│   └── security-scan.yml
├── analysis/
│   ├── agent1_module_map.md
│   ├── agent2_data_api_flows.md
│   └── agent3_deployment_ops_audit.md
├── backend/
│   ├── app/
│   │   ├── api/
│   │   ├── auth/
│   │   ├── core/
│   │   ├── db/
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── services/
│   │   ├── tests/
│   │   └── main.py
│   ├── alembic/
│   │   ├── env.py
│   │   └── versions/
│   ├── db/schema.sql
│   ├── Dockerfile
│   ├── Makefile
│   ├── alembic.ini
│   ├── run_migration.sh
│   ├── setup_db.sh
│   └── test_*.sh / QUICK_TEST.sh
├── docs/
├── ios/
├── scripts/
│   ├── s3_smoke_test.py
│   ├── secret-scan.sh
│   └── verify-security.sh
└── docker-compose.yml
```

Top-level directory purpose:
- `.github/workflows/`: CI, image build/push, security scans, and staging deploy template.
- `analysis/`: pre-generated agent analysis artifacts used for this synthesis.
- `backend/`: deployable backend service code, migrations, image build file, and backend-local helper scripts.
- `docs/`: project documentation.
- `ios/`: SwiftUI client (not backend deploy artifact).
- `scripts/`: repo-level operational/security helper scripts.
- `docker-compose.yml`: local dev runtime composition for API + Postgres.

Module ownership/boundaries (what should not depend on what):
- `backend/app/api/` should not own core business rules or long-lived transaction strategy; it should orchestrate request/response + call services.
- `backend/app/services/` should not depend on API routers/schemas.
- `backend/app/core/` should not depend on domain services. Current violation: `backend/app/core/idempotency.py` imports `app.services.expense.compute_request_hash`.
- `backend/app/models/` should be persistence-only and should not depend on API/service modules.
- `backend/app/schemas/` should remain transport contracts; tight coupling to ORM enums should be minimized.

# Runtime Entry Points & Startup
Primary backend entry points (exact file paths):
- `backend/app/main.py`: FastAPI app construction, router wiring, `/health`, `/expenses/{expense_id}`.
- `backend/alembic/env.py`: Alembic runtime bootstrap.

Workers/schedulers/jobs (exact file paths):
- No dedicated worker/scheduler module is present under `backend/app/`.
- OCR executes inline in request path via `backend/app/api/shopping.py` -> `backend/app/services/shopping.py` -> `backend/app/services/ocr.py`.

CLI tools (exact file paths):
- `backend/Makefile`
- `backend/run_migration.sh`
- `backend/setup_db.sh`
- `backend/test_api.sh`
- `backend/test_baseline.sh`
- `backend/QUICK_TEST.sh`
- `scripts/s3_smoke_test.py`
- `scripts/secret-scan.sh`
- `scripts/verify-security.sh`

Local dev commands:
- `docker-compose up -d db`
- `cd backend && python3 -m venv .venv && source .venv/bin/activate`
- `pip install -r requirements.txt` (or `requirements-dev.txt`)
- `alembic upgrade head`
- `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`
- `make run`, `make ci-pr`, `make ci-main`

Production startup command(s) (verifiable):
- `uvicorn app.main:app --host 0.0.0.0 --port 8000`
  - Verified in `backend/Dockerfile` (`CMD`) and `docker-compose.yml` (`services.api.command`).
- Migration execution is separate (`alembic upgrade head` via `backend/Makefile`/scripts), not embedded in container start command.

# Key Architectural Modules
## App bootstrap and runtime config
- Responsibility: app assembly, CORS policy, exception handling, router inclusion, health endpoint.
- Key files: `backend/app/main.py`, `backend/app/core/config.py`, `backend/app/db/session.py`.
- Public interfaces: `app`, `get_settings()`, `get_session()`.
- Dependencies:
  - Internal: API routers, auth dependency, service calls for expense retrieval.
  - External: FastAPI/Starlette, SQLAlchemy async engine, Pydantic settings.
- Coupling notes: config and DB engine are instantiated at import time; startup fails if non-local/test and `CORS_ORIGINS` is empty.

## API controllers
- Responsibility: HTTP route definitions and request orchestration.
- Key files: `backend/app/api/auth.py`, `backend/app/api/friends.py`, `backend/app/api/groups.py`, `backend/app/api/expenses.py`, `backend/app/api/settlements.py`, `backend/app/api/shopping.py`.
- Public interfaces: `router` objects included in `backend/app/main.py`.
- Dependencies:
  - Internal: services, schemas, auth dependencies, db session dependency.
  - External: FastAPI + SQLAlchemy query usage.
- Coupling notes: several handlers perform direct ORM reads/writes in controller layer instead of delegating fully to services.

## Auth and security utilities
- Responsibility: password hashing, JWT mint/validation, refresh token rotation, auth dependency resolution, rate limiting, idempotency utilities.
- Key files: `backend/app/auth/dependencies.py`, `backend/app/auth/jwt.py`, `backend/app/auth/password.py`, `backend/app/auth/refresh_tokens.py`, `backend/app/core/rate_limit.py`, `backend/app/core/idempotency.py`.
- Public interfaces: `get_current_user`, token helpers, `persist_refresh_token`, `validate_and_rotate_refresh_token`, rate-limit helpers, idempotency helpers.
- Dependencies:
  - Internal: models + DB session.
  - External: `PyJWT`, `bcrypt`, FastAPI security.
- Coupling notes: `core/idempotency.py` depends on `services/expense.py` for request hashing.

## Domain services: friends/groups/memberships/expenses/settlements
- Responsibility: authorization checks and core business operations.
- Key files: `backend/app/services/friends.py`, `backend/app/services/group.py`, `backend/app/services/membership.py`, `backend/app/services/expense.py`, `backend/app/services/settlement.py`.
- Public interfaces:
  - Friends: request/accept/decline/list flows with normalized user-pair invariants.
  - Group: membership/owner guards, group fetch/list/create.
  - Membership: lookup and add-member flows.
  - Expense: create equal-split expenses, read flows, idempotency hash helper.
  - Settlement: balances, batch computation, payment lifecycle, settlement status transitions.
- Dependencies:
  - Internal: models + db.
  - External: SQLAlchemy + FastAPI `HTTPException`.
- Coupling notes: commit ownership is inconsistent (some service functions commit directly, others rely on API-level commit).

## Domain services: shopping/receipts/OCR
- Responsibility: shopping session/item/split lifecycle, receipt storage abstraction, OCR extraction orchestration.
- Key files: `backend/app/services/shopping.py`, `backend/app/services/ocr.py`.
- Public interfaces: session/item/receipt CRUD helpers, authorization helpers, OCR extraction entrypoints, `ReceiptStorage`.
- Dependencies:
  - Internal: shopping/receipt models + config.
  - External: `boto3`, `Pillow`, `pytesseract`, `python-dotenv`.
- Coupling notes:
  - `backend/app/services/shopping.py` is large (1052 LOC) and combines storage, auth checks, and domain logic.
  - Global `receipt_storage = ReceiptStorage()` initializes S3 client at import time.

## Persistence and migration layer
- Responsibility: ORM entities, async session/engine, schema migration history.
- Key files: `backend/app/models/*.py`, `backend/app/db/__init__.py`, `backend/app/db/session.py`, `backend/alembic/env.py`, `backend/alembic/versions/*.py`.
- Public interfaces: `Base`, `engine`, `SessionLocal`, model classes.
- Dependencies:
  - Internal: used by API/services/auth/migrations.
  - External: SQLAlchemy + Alembic.
- Coupling notes: Alembic env imports full model package to build metadata.

## API contract schemas
- Responsibility: request/response models and validation contracts.
- Key files: `backend/app/schemas/*.py`.
- Public interfaces: Pydantic schema classes for auth/groups/expenses/settlements/shopping/users.
- Dependencies:
  - Internal: consumed by API routes.
  - External: Pydantic v2.
- Coupling notes: some schema typing references ORM enums.

# Data Layer
Datastores and roles:
- PostgreSQL: primary transactional datastore for auth, groups, memberships, expenses, settlements, shopping, receipts, idempotency, refresh tokens.
- Amazon S3: receipt object storage and presigned download URLs.
- In-memory process state: rate limiting counters (`InMemoryRateLimiter`), OCR concurrency semaphore.
- Queue/cache datastore: none evidenced in backend source.

Connection/config and relevant env vars:
- Database connection: `DATABASE_URL` via `backend/app/core/config.py` -> used in `backend/app/db/session.py` and `backend/alembic/env.py`.
- S3/OCR controls: `AWS_REGION`, `S3_BUCKET_NAME`, `S3_PRESIGNED_GET_EXPIRE_SECONDS`, `S3_PREFIX`, `MAX_RECEIPT_BYTES`, `MAX_RECEIPT_PIXELS`, `MAX_OCR_CONCURRENCY` via `backend/app/core/config.py` and shopping/ocr services.

Schema location, migrations, seeds:
- ORM models: `backend/app/models/`.
- Migration source of truth: `backend/alembic/versions/`.
- Migration runtime: `backend/alembic/env.py`, `backend/alembic.ini`.
- Reference snapshot: `backend/db/schema.sql` explicitly says Alembic is source of truth.
- Seed mechanism: no dedicated seed command/script evidenced; only example inserts in `backend/db/schema.sql` (reference file).

Data access pattern:
- Async SQLAlchemy ORM (`AsyncSession`, `select`, `flush`, `refresh`, `commit`) across API and services.
- `selectinload` used for eager loading in multiple service paths.
- Raw SQL usage is minimal and explicit (e.g., `SELECT 1` in health endpoint).

Consistency/transactions (verifiable):
- DB-level integrity via constraints/triggers in migrations, including deferred split-sum enforcement and shopping membership integrity migration (`20260213_0010_shopping_membership_integrity.py`).
- Refresh token rotation uses row locking with `SELECT ... FOR UPDATE` in `backend/app/auth/refresh_tokens.py`.
- Transaction boundary ownership is mixed (handler-level commits plus service-level commits).

# API Layer & Request Pipeline (if applicable)
Routing and handler structure:
- App router inclusion in `backend/app/main.py`.
- Prefixes:
  - `/auth` -> `backend/app/api/auth.py`
  - `/groups` -> `backend/app/api/groups.py`, `backend/app/api/expenses.py`
  - no router prefix (absolute route paths) -> `backend/app/api/settlements.py`, `backend/app/api/shopping.py`
- App-level routes: `/health`, `/expenses/{expense_id}` in `backend/app/main.py`.

Middleware/interceptors:
- `CORSMiddleware` in `backend/app/main.py`.
- Validation exception handler for `RequestValidationError` in `backend/app/main.py`.
- Dependency-based injection for auth and DB session (`Depends(get_current_user)`, `Depends(get_session)`).

AuthN/AuthZ enforcement points:
- AuthN: bearer JWT parsing/validation in `backend/app/auth/dependencies.py` + `backend/app/auth/jwt.py`.
- AuthZ: service-level guards in `backend/app/services/group.py`, `backend/app/services/shopping.py`, and settlement authorization helpers in `backend/app/services/settlement.py`.

Validation strategy:
- Pydantic schema validation (`backend/app/schemas/*.py`).
- Business-rule validation in services/API handlers (membership role checks, payer/uploader constraints, one-receipt rule).
- DB constraints/triggers enforce additional invariants.

Error handling strategy:
- Domain failures raised as `HTTPException` across API/services.
- Request validation returns explicit 422 payload via custom exception handler.
- Unhandled exceptions rely on FastAPI default 500 handling.
- Some explicit rollback logic is local (for example, user creation path in `backend/app/api/auth.py`).

# Friends Feature (MVP)
## New data model
- New model: `backend/app/models/friendship.py` (`Friendship`, `FriendshipStatus`).
- New migration: `backend/alembic/versions/20260214_0011_friendships_table.py`.
- New table: `friendships`.
  - Columns:
    - `id UUID PRIMARY KEY DEFAULT uuid_generate_v4()`
    - `user_low_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
    - `user_high_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
    - `requested_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
    - `status friendship_status NOT NULL DEFAULT 'pending'`
    - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
    - `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`
  - Enum values: `pending`, `accepted`, `declined`.
  - Constraints/invariants:
    - `UNIQUE (user_low_id, user_high_id)` ensures one row per user pair.
    - `CHECK (user_low_id <> user_high_id)` disallows self friendship rows.
    - `CHECK (requested_by_user_id = user_low_id OR requested_by_user_id = user_high_id)` ensures requester is one of the pair.
  - Indexes:
    - `idx_friendships_status_user_low (status, user_low_id)`
    - `idx_friendships_status_user_high (status, user_high_id)`
  - Trigger:
    - `friendships_set_updated_at` updates `updated_at` via shared `set_updated_at()` trigger function.
- Pair normalization rule (service + schema invariant): friendship pairs are always normalized to `(min(user_id), max(user_id))` before insert/update lookup.

## New API endpoints
- Router: `backend/app/api/friends.py` (included in `backend/app/main.py`).
- Endpoints (all authenticated via `get_current_user`):
  - `POST /friends/requests`
    - Input: `FriendRequestCreate { to_user_id }`
    - Responsibility: create a pending request or apply request-state policy for existing row.
  - `POST /friends/requests/{friendship_id}/accept`
    - Responsibility: receiver-only transition from pending to accepted.
  - `POST /friends/requests/{friendship_id}/decline`
    - Responsibility: receiver-only transition from pending to declined.
  - `GET /friends?q=...`
    - Responsibility: list accepted friendships for current user; optional case-insensitive search within current user’s friend list only.

## New service module and business rules
- Service module: `backend/app/services/friends.py`.
- Layer responsibilities:
  - API layer performs orchestration (dependency injection, request/response mapping, `commit()`).
  - Service layer owns friendship business logic and invariant enforcement (`flush()`, conflict mapping).
  - Model layer remains persistence only.
  - Schema layer defines transport contracts (`backend/app/schemas/friends.py`).
- Implemented rules:
  - `send_friend_request`:
    - Reject self-request (`400`).
    - If existing friendship is `accepted`, return `409`.
    - If existing friendship is `pending` and already requested by same sender, return `409`.
    - If existing friendship is `pending` requested by the other user, auto-accept (policy decision).
    - If existing friendship is `declined`, allow re-request by resetting to `pending` and updating `requested_by_user_id` (policy decision).
  - `accept_friend_request` / `decline_friend_request`:
    - Only request receiver may act (`403` for sender).
    - Only valid when current status is `pending` (`400` otherwise).
  - `list_friends`:
    - Returns only `accepted` rows involving current user.
    - Computes the “other user” via SQL `CASE` and joins to `users` in one query (no per-row friend lookup/N+1).
    - Optional `q` filter applies server-side (`ILIKE`) across `username`, `first_name`, `last_name`.
  - Integrity collisions (`IntegrityError`) are mapped to HTTP `409`.

## Friends data flow
- Request lifecycle:
  - `POST /friends/requests` -> normalize pair -> `SELECT ... FOR UPDATE` existing row -> create/update row -> `flush` in service -> `commit` in API -> return `FriendshipOut`.
- Acceptance flow:
  - `POST /friends/requests/{id}/accept` -> authorize participant + receiver role -> state transition `pending -> accepted` -> flush/commit -> return current friendship + friend projection.
- Decline flow:
  - `POST /friends/requests/{id}/decline` -> authorize participant + receiver role -> state transition `pending -> declined` -> flush/commit -> return current friendship + friend projection.
- Search flow:
  - `GET /friends?q=...` -> single joined query limited to accepted rows where current user participates -> optional case-insensitive filter -> serialized friend-safe output fields only.

## Architectural tradeoffs and decisions
- Pair normalization tradeoff:
  - Chosen to represent an undirected relationship as one canonical row; this simplifies uniqueness and lookup logic.
- Reverse pending auto-accept policy:
  - Chosen for lower user friction and deterministic handling of crossed requests.
- Re-request after decline policy:
  - Allowed by resetting existing row to `pending` instead of creating a second row; this preserves history shape and keeps one-row-per-pair invariant.

# Integration Points
Third-party services explicitly referenced:
- PostgreSQL
  - Configured by `DATABASE_URL` in `backend/app/core/config.py`.
  - Called from `backend/app/db/session.py` and migrations (`backend/alembic/env.py`).
- Amazon S3 (`boto3`)
  - Configured by S3/AWS env vars in `backend/app/core/config.py`.
  - Called in `backend/app/services/shopping.py` (`put_object`, `get_object`, `delete_object`, `generate_presigned_url`).
  - Optional smoke utility: `scripts/s3_smoke_test.py`.
- OCR via Tesseract (`pytesseract` + Pillow)
  - Runtime deps installed in `backend/Dockerfile`.
  - Called in `backend/app/services/ocr.py` and invoked from `backend/app/services/shopping.py`.
- GitHub Container Registry (`ghcr.io`) for image publishing
  - Configured in `.github/workflows/docker.yml`.

# Configuration & Secrets
Config loading mechanism:
- Primary config: `backend/app/core/config.py` (`BaseSettings`) with `env_file=(".env", "../.env")` and cached `get_settings()`.
- Additional loading path: `backend/app/services/shopping.py` explicitly calls `load_dotenv()` for `backend/.env` if present.

Env var table:

| Name | Purpose | Where referenced |
|---|---|---|
| `ENV` | runtime mode flags (`local/test/production`) | `backend/app/core/config.py`, `backend/app/main.py`, `backend/app/core/rate_limit.py` |
| `DATABASE_URL` | async DB connection for app + Alembic | `backend/app/core/config.py`, `backend/app/db/session.py`, `backend/alembic/env.py` |
| `JWT_SECRET` | JWT signing key | `backend/app/core/config.py`, `backend/app/auth/jwt.py` |
| `JWT_ALGORITHM` | JWT algorithm | `backend/app/core/config.py`, `backend/app/auth/jwt.py` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | access-token TTL | `backend/app/core/config.py`, `backend/app/auth/jwt.py` |
| `REFRESH_TOKEN_EXPIRE_DAYS` | refresh-token TTL | `backend/app/core/config.py`, `backend/app/auth/jwt.py` |
| `CORS_ORIGINS` | allowed CORS origins | `backend/app/core/config.py`, `backend/app/main.py` |
| `TRUST_PROXY_HEADERS` | trust proxy headers for client IP derivation | `backend/app/core/config.py`, `backend/app/core/rate_limit.py` |
| `TRUSTED_PROXY_IPS` | trusted proxy CIDRs/IPs | `backend/app/core/config.py`, `backend/app/core/rate_limit.py` |
| `RATE_LIMIT_MAX_KEYS` | in-memory rate-limit key cap | `backend/app/core/config.py`, `backend/app/core/rate_limit.py` |
| `AWS_REGION` | S3 region | `backend/app/core/config.py`, `backend/app/services/shopping.py` |
| `S3_BUCKET_NAME` | receipt storage bucket | `backend/app/core/config.py`, `backend/app/services/shopping.py`, `backend/app/main.py` |
| `S3_PRESIGNED_GET_EXPIRE_SECONDS` | presigned URL TTL | `backend/app/core/config.py`, `backend/app/services/shopping.py`, `backend/app/api/shopping.py` |
| `S3_PREFIX` | receipt object key prefix | `backend/app/core/config.py`, `backend/app/services/shopping.py` |
| `MAX_RECEIPT_BYTES` | upload size limit | `backend/app/core/config.py`, `backend/app/services/shopping.py` |
| `MAX_RECEIPT_PIXELS` | image safety limit | `backend/app/core/config.py`, `backend/app/services/shopping.py`, `backend/app/services/ocr.py` |
| `MAX_OCR_CONCURRENCY` | OCR concurrency cap | `backend/app/core/config.py`, `backend/app/services/ocr.py` |
| `AWS_ACCESS_KEY_ID` | AWS credential (via boto3 credential chain) | process env consumed by `backend/app/services/shopping.py`/`boto3` |
| `AWS_SECRET_ACCESS_KEY` | AWS credential (via boto3 credential chain) | process env consumed by `backend/app/services/shopping.py`/`boto3` |
| `POSTGRES_USER` | local/CI Postgres bootstrap user | `docker-compose.yml`, `.github/workflows/ci.yml`, `backend/setup_db.sh` |
| `POSTGRES_PASSWORD` | local/CI Postgres bootstrap password | `docker-compose.yml`, `.github/workflows/ci.yml` |
| `POSTGRES_DB` | local/CI Postgres DB name | `docker-compose.yml`, `.github/workflows/ci.yml`, `backend/setup_db.sh` |
| `POSTGRES_PORT` | local Postgres port mapping | `docker-compose.yml`, `.env.example` |

Secrets handling and risks:
- `DATABASE_URL` and `JWT_SECRET` are modeled as `SecretStr` in `backend/app/core/config.py`.
- `.env` and `backend/.env` files are gitignored (`.gitignore`), and `git check-ignore` confirms both are ignored.
- Workspace risk observed: `.env` and `backend/.env` exist with non-empty `DATABASE_URL`, `JWT_SECRET`, `AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY` values.
- `backend/app/services/shopping.py` explicit `.env` loading introduces config-source fragmentation versus centralized settings-only loading.
- `.env.example` does not list every runtime-sensitive variable from `Settings` (for example `CORS_ORIGINS`, proxy/rate-limit vars, OCR concurrency).

Local vs prod differences (explicit):
- Non-local/test startup requires non-empty `CORS_ORIGINS`; otherwise app startup raises `RuntimeError`.
- `/health` returns detailed dependency fields only when `ENV in {local, test}`.
- Rate limiting disabled in `ENV=test`.
- CORS credential behavior differs: local/test uses `allow_credentials=False`, non-local/test uses `True`.

# Build, Test, and Tooling
Build commands and artifacts:
- Local backend build/runtime:
  - `backend/Makefile`: `install`, `install-dev`, `run`, `migrate`, `ci-pr`, `ci-main`.
- Container build:
  - `backend/Dockerfile` builds runtime image.
  - `.github/workflows/docker.yml` builds/pushes image to GHCR.
  - `.github/workflows/ci.yml` performs archive image build on main (`backend-archive-main`).

Test commands/frameworks:
- Frameworks: `pytest`, `pytest-asyncio`, `httpx`, `pytest-cov` (see `backend/requirements*.txt`).
- Commands:
  - `make test-pr` (`pytest -m "not e2e" ...`)
  - `make test-all` (`pytest ...` full suite)
  - `make ci-pr`, `make ci-main`
- Test config: `backend/pytest.ini` with `e2e` marker.

Lint/format/typecheck tooling:
- CI lint gate: `ruff` fatal rules only (`E9,F63,F7,F82`) in `backend/Makefile` and `.github/workflows/ci.yml`.
- Type checker dependency `mypy` exists in `backend/requirements-dev.txt`, but no CI step invokes it.
- `black` and `isort` dependencies exist in dev requirements; no enforced CI invocation found.

Codegen steps:
- No code-generation step is evidenced in backend build/test workflows.

# Observability & Operations
Logging strategy:
- Module-level Python loggers (`logging.getLogger(__name__)`) in app/services.
- No centralized runtime logging configuration file/module for application logs was found.
- Alembic logging configured in `backend/alembic.ini`.

Metrics/tracing/error reporting:
- No Prometheus/OpenTelemetry/StatsD instrumentation found in backend source.
- No external error-reporting integration (Sentry/Rollbar/Bugsnag) found.

Health checks/readiness endpoints:
- `GET /health` in `backend/app/main.py` checks DB connectivity (`SELECT 1`) and reports S3 only as configuration presence (`bool(settings.s3_bucket_name)`), not a live S3 probe.
- `docker-compose.yml` defines healthcheck for `db` service; no API container healthcheck is defined.

# CI/CD & Deployment Readiness
CI/CD workflows and what they run (file paths):
- `.github/workflows/ci.yml`
  - Lint gate, migration up/down/up validation, PR test suite, main full suite, archive image build artifact.
- `.github/workflows/docker.yml`
  - Buildx build/push to GHCR + Trivy SARIF upload.
- `.github/workflows/security-scan.yml`
  - TruffleHog secret scan, safety/pip-audit dependency checks, Bandit scan, summary.
- `.github/workflows/deploy-staging.yml`
  - Template-only staging workflow (image pull + placeholder health/rollback echo steps).

Containerization/orchestration:
- Present: `backend/Dockerfile`, `docker-compose.yml`.
- Kubernetes/Helm/Terraform deployment manifests: none found in repo.

Deployment assumptions:
- Deployment target platform/orchestrator is not concretely implemented in repository workflows/manifests.
- Migration rollout mechanism in production pipeline is not implemented in `deploy-staging.yml`.
- Runtime scaling topology (single worker vs multiple workers/replicas) is not encoded in deploy assets.

Deployment Readiness Score (1–10): **4/10**
- Why: backend has a functional container build, migration tooling, and CI test gates, but production deployment automation is template-level, observability is minimal, security scans are partly non-blocking, and config/secrets practices are not yet production-hard.

Must-fix before deploy blockers:
- Replace template deployment workflow with real deploy steps (rollout, migration gate, health verification, rollback path).
- Remove dependence on local `.env` files for deployed runtime secrets; enforce platform secret injection.
- Add startup/config validation for complete production env requirements and document them.
- Add API/container readiness checks (including meaningful external dependency checks).
- Define and enforce security-scan blocking policy for deployment path.

# Architectural Risks & Technical Debt Hotspots
Coupling, circular deps, leaky abstractions:
- Boundary leak: `backend/app/core/idempotency.py` depends on `backend/app/services/expense.py`.
- Controller/ORM coupling across multiple route modules.
- Large hotspot modules:
  - `backend/app/services/shopping.py` (1052 LOC)
  - `backend/app/api/shopping.py` (934 LOC)
  - `backend/app/services/settlement.py` (683 LOC)
- No runtime circular dependency was reported in agent import-graph analysis.

Security risks (evidenced):
- Non-empty secret-bearing `.env` files are present in workspace (`.env`, `backend/.env`).
- Explicit `load_dotenv()` path in `backend/app/services/shopping.py` can bypass centralized secret delivery expectations.
- Security scans in `.github/workflows/security-scan.yml` include non-blocking commands (`|| true`) for dependency/code scans.

Performance/scaling risks (evidenced):
- Process-local in-memory rate limiter is not shared across replicas/workers.
- Synchronous S3 calls (`put_object`, `delete_object`) execute in async request paths without thread offloading.
- Settlement recomputation is on write paths (expense creation/payment confirmation), increasing latency as data grows.
- Query-shape inefficiencies are present in some handler loops (repeated per-item/per-group queries).

Testability gaps:
- No enforced type-check gate in CI despite mypy dependency.
- Coverage artifacts are generated, but no coverage threshold enforcement found.
- Production deployment workflow is template-only, so release-path behavior is not continuously tested.

# Backend Deployment Plan (Staged, Practical)
## Stage 0: Baseline safety (tests, env validation, logging)
Objective: establish deterministic pre-deploy safety checks.
- Add a backend preflight script that validates required env vars for deploy environments.
- Add CI gate to fail on migration drift and run `make ci-main` on release branch/tag path.
- Add baseline structured logging config (request id, user id/membership id where safe, endpoint, status, latency).
- Add API container healthcheck in container runtime config.

## Stage 1: Config/secrets hardening
Objective: remove local-file secret coupling and define one secret source of truth.
- Remove `load_dotenv()` dependency in `backend/app/services/shopping.py`; consume settings/env only.
- Expand `.env.example` to include all settings keys used by `backend/app/core/config.py`.
- Document required production env vars and defaults in one deploy-facing doc.
- Rotate credentials currently stored in local `.env` files and move to secret manager/CI secret store.

## Stage 2: Containerization and runtime parity
Objective: make local/staging/prod runtime behavior consistent.
- Add runtime command policy (workers/replicas/proxy strategy) and codify it in deployment config.
- Add explicit readiness checks for DB and S3 behavior appropriate to environment.
- Add container startup contract: app starts only when critical config is valid.
- Validate OCR runtime parity (Tesseract package/version) across CI/staging/prod images.

## Stage 3: CI/CD + release pipeline
Objective: promote from tested artifact to deployed artifact with gating.
- Replace `.github/workflows/deploy-staging.yml` template with real deployment steps.
- Add migration step policy (pre-deploy/init-job) and fail deployment if migration fails.
- Gate deployment on CI success + security policy outcomes.
- Align Docker scan image reference with actual built tags/digests.

## Stage 4: Production readiness (monitoring, backups, rollbacks)
Objective: operationalize runtime reliability and incident response.
- Add centralized log shipping and alerting on error-rate/latency/health degradation.
- Add DB backup/restore runbook and scheduled backup verification.
- Add rollback playbook tied to deployment workflow.
- Add SLO-oriented dashboards (availability, p95 latency, failed auth, failed uploads, failed OCR).

# Top 10 Action Items (Prioritized for Deployment)
1. Implement a real deployment workflow in `.github/workflows/deploy-staging.yml` (impact: converts template to executable release path).
2. Eliminate runtime secret loading from local files (`backend/app/services/shopping.py`) and enforce secret-manager/env injection (impact: major security and operability gain).
3. Add complete production env contract and startup validation for all required keys (impact: prevents misconfigured boot failures).
4. Add DB migration execution as an explicit deployment gate (impact: prevents runtime/schema mismatch incidents).
5. Add API readiness checks and container healthcheck beyond DB-only signals (impact: better rollout safety and orchestration behavior).
6. Make security scans actionable by defining blocking policy for dependency/code findings (impact: reduces vulnerable deploys).
7. Refactor blocking S3 operations in async request paths to thread-offload or async-compatible pattern (impact: protects event-loop latency under load).
8. Standardize transaction boundaries (handler vs service commits) across domains (impact: reduces partial-write/consistency risk).
9. Split `shopping` and `settlement` hotspots into narrower modules with clearer interfaces (impact: improves maintainability and change safety).
10. Add CI type-check gate (`mypy`) and minimum coverage threshold policy (impact: catches regressions earlier in deploy path).

# Confidence & Unknowns
What was verified directly from code:
- Entry points and startup commands (`backend/app/main.py`, `backend/Dockerfile`, `docker-compose.yml`, `backend/Makefile`).
- Config sources and env var usage (`backend/app/core/config.py`, `backend/app/services/shopping.py`, workflows, compose).
- ORM/migrations/data model locations (`backend/app/models/`, `backend/alembic/`, `backend/alembic/env.py`).
- CI/CD and security workflow behavior (`.github/workflows/*.yml`).
- Deployment artifact presence/absence (Docker/Compose present; no k8s/helm manifests found).

Unknowns and what to check next:
- Unknown – requires clarification: Production hosting/orchestration target (ECS/Kubernetes/VM/PaaS). Check deployment platform repo or infrastructure team source of truth.
- Unknown – requires clarification: Production migration rollout strategy (pre-deploy job/init container/manual). Check release runbook and deployment pipeline design.
- Unknown – requires clarification: Runtime scaling model (worker count, replica policy, autoscaling). Check runtime service definition and load balancer configuration.
- Unknown – requires clarification: Production secret manager and rotation process. Check platform secret-management policy and audit controls.
- Unknown – requires clarification: Centralized observability stack (log aggregation, metrics, tracing, on-call alert routing). Check ops/incident tooling configuration.

Minimal assumptions used:
- “No worker framework” is based on source scan of backend Python modules.
- “No Kubernetes/Helm/Terraform manifests” is based on repository file scan only.
- Deployment readiness scoring is based on code/workflow evidence in this repository, not external infra.
