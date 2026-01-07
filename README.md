# ClearSplit Monorepo

Splitwise-style group expense and settlement tracker. Backend is the source of truth; iOS is the client. Architecture, scope, and non-negotiables are locked from the project brief.

## Structure
- `.github/workflows/` — CI/CD pipelines (backend lint/type/test, iOS build/tests, docker build, deploy to staging).
- `backend/` — FastAPI service, SQLAlchemy models, Alembic migrations, settlement engine.
- `ios/` — SwiftUI app using MVVM; networking client for the API; Keychain token storage.
- `docs/` — ADRs and design docs (DB schema, auth/token strategy).
- `docker-compose.yml` — Local dev stack (API + Postgres).
- `.env.example` — Environment variables for local and CI.

## Product Features

ClearSplit is now focused on **Shopping Sessions** — a powerful roommates grocery receipt splitting tool with item-level equal splits.

### Shopping Sessions
- Create shopping trips with title, date, and payer
- Add participants from your group members
- Upload receipt images (optional)
- Add line items manually (name, price, quantity)
- Assign sharers to each item
- Automatic equal split calculations
- Deterministic remainder distribution

See [SHOPPING_MODEL.md](./SHOPPING_MODEL.md) and [HOW_TO_TEST_SHOPPING.md](./HOW_TO_TEST_SHOPPING.md) for comprehensive documentation.

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
5. **Shopping Sessions (NEW)** — Grocery receipt splitting with item-level equal splits.
6. CI/CD & Deployment (staging auto-deploy on PR, required checks).

## Local Setup (macOS)

### Prerequisites
- Docker Desktop installed and running
- Python 3.11+ (`python3 --version`)
- Xcode 15+ with Command Line Tools (`xcodebuild -version`)

### Backend Setup

1. **Create environment file:**
   ```bash
   cp .env.example .env
   # Edit .env and ensure DATABASE_URL and JWT_SECRET are set
   ```

2. **Start PostgreSQL database:**
   ```bash
   docker-compose up -d db
   ```
   Expected: Container starts and healthcheck passes. Verify with `docker-compose ps`.

3. **Install Python dependencies:**
   ```bash
   cd backend
   make install
   ```
   Expected: Packages install successfully.

4. **Run database migrations:**
   ```bash
   alembic upgrade head
   ```
   Expected: Migrations apply successfully:
   - `20241218_0001_initial` — Core tables (users, groups, expenses, etc.)
   - `20250107_0002_add_shopping_tables` — Shopping sessions and items

5. **Start backend server:**
   ```bash
   make run
   ```
   Expected: Server starts on `http://0.0.0.0:8000`. Test with:
   ```bash
   curl http://localhost:8000/health
   ```
   Expected output: `{"status":"ok"}`

6. **Run tests:**
   ```bash
   make test
   ```
   Expected: `test_health` passes.

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
