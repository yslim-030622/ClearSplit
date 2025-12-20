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

## Local Setup (macOS)

### Prerequisites
- Docker Desktop installed and running
- Python 3.11+ (`python3 --version`)
- Xcode 15+ with Command Line Tools (`xcodebuild -version`)

### Backend Setup

1. **Create environment file:**
   ```bash
   cp .env.example .env.local
   # Generate a JWT secret:
   openssl rand -hex 32
   # Edit .env.local and fill in real values (DATABASE_URL, JWT_SECRET)
   # NEVER commit .env.local - it's gitignored!
   ```

2. **Start PostgreSQL database:**
   ```bash
   docker-compose --env-file .env.local up -d db
   ```
   Expected: Container starts and healthcheck passes. Verify with `docker-compose ps`.

3. **Install Python dependencies:**
   ```bash
   cd backend
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
   Expected: Packages install successfully.

4. **Run database migrations:**
   ```bash
   # Ensure .env.local is in backend/ or parent directory
   alembic upgrade head
   ```
   Expected: Migration applies successfully. Tables created in Postgres.

5. **Start backend server:**
   ```bash
   # With .env.local in backend/ directory:
   uvicorn app.main:app --reload
   ```
   Expected: Server starts on `http://0.0.0.0:8000`. Test with:
   ```bash
   curl http://localhost:8000/health
   ```
   Expected output: `{"status":"ok"}`

6. **Run tests:**
   ```bash
   # Tests use dummy secrets from conftest fixtures
   pytest -q
   ```
   Expected: All 48 tests pass.

### Security Setup

**Before committing any code:**

```bash
# Run the secret scanner
./scripts/secret-scan.sh
```

This detects hardcoded secrets. If found, **DO NOT COMMIT**. See `SECURITY.md` for details.

**Key security rules:**
- ✅ Use `.env.local` (gitignored) for local secrets
- ✅ Generate strong JWT secrets: `openssl rand -hex 32`
- ❌ Never commit real secrets to git
- ❌ Never hardcode passwords in code

See `SECURITY.md` for complete security policy.

### iOS Setup

1. **Open in Xcode:**
   ```bash
   open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
   ```
   Or build from command line:
   ```bash
   cd ios/ClearSplit
   xcodebuild -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15' build
   ```
   Expected: Project compiles without errors.

2. **Run tests:**
   ```bash
   xcodebuild test -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15'
   ```
   Expected: Tests pass (if any exist).

### Verification Checklist

- [ ] Backend starts via `docker-compose up -d db` and `make run`
- [ ] `GET /health` returns `{"status":"ok"}`
- [ ] Alembic `upgrade head` runs successfully against local Postgres
- [ ] iOS project compiles via Xcode or `xcodebuild`
- [ ] `.gitignore` does NOT ignore `project.pbxproj`
- [ ] `.gitignore` ignores `DerivedData/` and `xcuserdata/`
