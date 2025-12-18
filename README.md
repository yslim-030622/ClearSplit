# ClearSplit Monorepo

Splitwise-style group expense and settlement tracker. Backend is the source of truth; iOS is the client. Architecture, scope, and non-negotiables are locked from the project brief.

## Structure
- `.github/workflows/` — CI/CD pipelines (backend lint/type/test, iOS build/tests, docker build, deploy to staging).
- `backend/` — FastAPI service, SQLAlchemy models, Alembic migrations, settlement engine.
- `ios/` — SwiftUI app using MVVM; networking client for the API; Keychain token storage.
- `docs/` — ADRs and design docs (DB schema, auth/token strategy).
- `docker-compose.yml` — Local dev stack (API + Postgres).
- `.env.example` — Environment variables for local and CI.

## Non-negotiables
- Money stored as integer cents (bigint); no floats/decimals.
- Expense creation is atomic (single DB transaction).
- Settlement results are immutable snapshots (status-only changes; new batch to re-run).
- Idempotency keys on all writes.
- Timestamps stored/transmitted as UTC ISO-8601.

## Vertical slice phases
0. Foundation (walking skeleton, health, logging, idempotency middleware stub).
1. Authentication (email/password, JWT access+refresh with rotation).
2. Groups & Membership (roles: owner, member, optional viewer).
3. Expenses (equal split only; splits recorded).
4. Settlement Engine (minimal transfers; snapshot + status tracking).
5. CI/CD & Deployment (staging auto-deploy on PR, required checks).

## Local setup (outline)
1) Copy `.env.example` to `.env` and fill values.  
2) Start DB: `docker-compose up -d db`.  
3) Run migrations: `cd backend && make install && alembic upgrade head`.  
4) Start backend: `cd backend && make run`.  
5) Run tests: `cd backend && make test`.  
6) iOS: open `ios/ClearSplit` package in Xcode or build via `xcodebuild test -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15'`.
