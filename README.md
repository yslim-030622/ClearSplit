# ClearSplit

Expense-splitting API built with FastAPI, PostgreSQL 16, and SQLAlchemy 2.0 async. Tracks group expenses, shopping sessions with receipt OCR, and computes minimum-transfer settlements using deterministic integer-cent arithmetic. Consumed by a native SwiftUI iOS client over HTTPS/JSON with JWT auth.

## Quick Links

- [Security Policy](SECURITY.md)
- [iOS App Showcase](SHOWCASE.md)

---

## Backend Architecture

```mermaid
graph TB
    subgraph "Clients"
        iOS["iOS App · SwiftUI"]
        Web["Any HTTP Client"]
    end

    subgraph "Backend · Python 3.11"
        direction TB
        ASGI["Uvicorn ASGI Server"]
        MW["Middleware<br/>CORS · Security Headers · Validation Sanitizer"]
        RL["Rate Limiter<br/>Sliding Window · Per-IP"]
        IK["Idempotency Gate<br/>Idempotency-Key Header"]
        JWT["JWT Auth<br/>HS256 · 15min Access · 30d Refresh"]

        subgraph API_LAYER["API Layer"]
            AUTH_R["/auth"]
            GRP_R["/groups"]
            EXP_R["/expenses"]
            SHOP_R["/shopping"]
            SETTLE_R["/settlements"]
            FRIEND_R["/friends"]
        end

        subgraph "Service Layer"
            SVC["Business Logic<br/>Auth Checks · Split Engine<br/>Balance Aggregator · Transfer Minimizer"]
        end

        ASGI --> MW --> RL --> IK --> JWT
        JWT --> API_LAYER
        API_LAYER --> SVC
    end

    subgraph "Data Stores"
        PG["PostgreSQL 16<br/>17 tables · Alembic migrations"]
        S3["AWS S3<br/>Receipt images · Presigned URLs"]
        OCR["Tesseract OCR<br/>In-process · Concurrency cap"]
    end

    iOS -- "HTTPS / Bearer JWT" --> ASGI
    Web -- "HTTPS / Bearer JWT" --> ASGI
    SVC --> PG
    SVC --> S3
    SVC --> OCR
```

| Layer | Stack | Purpose |
|-------|-------|---------|
| ASGI | Uvicorn + FastAPI 0.122 | Async request handling, OpenAPI docs (local only) |
| ORM | SQLAlchemy 2.0 async + asyncpg | Non-blocking DB access, relationship loading |
| Database | PostgreSQL 16 | ACID for financial data, check constraints, cascade deletes |
| Migrations | Alembic (14 revisions) | Schema versioning with upgrade/downgrade |
| Auth | PyJWT HS256 + bcrypt | Stateless access tokens, refresh rotation with JTI chain |
| Storage | boto3 S3 | Private receipt bucket, presigned GET URLs (15-min TTL) |
| OCR | pytesseract + Pillow | In-process text extraction, concurrency-limited (default 2) |
| Config | pydantic-settings + SecretStr | Typed env loading, secrets never in logs |

---

## Server / API

40+ endpoints across 6 domain routers. OpenAPI at `/docs` when `ENV=local`.

### Auth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/signup` | No | Create account. Rate: 5/5min per IP |
| POST | `/auth/login` | No | Authenticate. Rate: 10/60s per IP. Timing-safe (dummy hash on unknown user) |
| POST | `/auth/refresh` | No | Rotate refresh token. Revokes old JTI, persists new. Rate: 20/60s per IP |
| GET | `/auth/me` | Yes | Current user profile |

### Groups & Members

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/groups` | Yes | Create group; creator becomes owner |
| GET | `/groups` | Yes | List user's groups |
| GET | `/groups/{id}` | Yes | Get group (member required) |
| DELETE | `/groups/{id}` | Yes | Delete group (owner only, cascades) |
| POST | `/groups/{id}/members/preview` | Yes | Check user existence before invite (owner, rate-limited) |
| POST | `/groups/{id}/members` | Yes | Add member (owner only) |
| GET | `/groups/{id}/members` | Yes | List members |

### Expenses

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/groups/{id}/expenses` | Yes | Create with equal splits. Supports `Idempotency-Key` |
| GET | `/groups/{id}/expenses` | Yes | List group expenses |
| GET | `/expenses/{id}` | Yes | Get by ID (standalone route) |

### Settlements

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/groups/{id}/balances` | Yes | Live balances + suggested transfers |
| POST | `/groups/{id}/settlements/compute` | Yes | Persist immutable settlement batch. Idempotent |
| GET | `/groups/{id}/settlements/{batch_id}` | Yes | Get batch |
| POST | `/groups/{id}/settlements/{batch_id}/pay` | Yes | Create payment record |
| PATCH | `/groups/{id}/settlements/payments/{pid}` | Yes | Confirm payment (receiver or owner) |
| DELETE | `/groups/{id}/settlements/payments/{pid}` | Yes | Void payment |

### Shopping Sessions

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/groups/{id}/shopping-sessions` | Yes | Create session |
| GET | `/groups/{id}/shopping-sessions` | Yes | List sessions |
| GET | `/shopping-sessions/{id}` | Yes | Get with items, participants, receipts |
| PATCH | `/shopping-sessions/{id}` | Yes | Update title, date, total, status |
| POST | `/shopping-sessions/{id}/finalize` | Yes | Finalize session |
| DELETE | `/shopping-sessions/{id}` | Yes | Delete (cascades items, splits, receipts) |
| PUT | `/shopping-sessions/{id}/participants` | Yes | Set/replace participants |
| POST | `/shopping-sessions/{id}/items` | Yes | Create item |
| PATCH | `/items/{id}` | Yes | Update item (invalidates splits if total changes) |
| DELETE | `/items/{id}` | Yes | Delete item (cascades splits) |
| PUT | `/items/{id}/sharers` | Yes | Set sharers with equal-split computation |
| POST | `/shopping-sessions/{id}/receipt` | Yes | Upload receipt (one per session, 10MB/25MP limit) |
| GET | `/receipts/{id}/download-url` | Yes | Presigned S3 URL (15-min TTL) |
| DELETE | `/receipts/{id}` | Yes | Delete receipt from S3 |
| POST | `/receipts/{id}/extract-items` | Yes | OCR extraction (idempotent) |
| GET | `/receipts/{id}/extracted-items` | Yes | List extracted items |

### Friends

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/friends/requests` | Yes | Send request (by user_id or identifier) |
| POST | `/friends/requests/{id}/accept` | Yes | Accept |
| POST | `/friends/requests/{id}/decline` | Yes | Decline |
| GET | `/friends` | Yes | List accepted (optional search) |
| GET | `/friends/requests/incoming` | Yes | Incoming requests |
| GET | `/friends/requests/outgoing` | Yes | Outgoing requests |
| DELETE | `/friends/{id}` | Yes | Remove friendship |

### Health

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health/live` | Liveness probe (always 200) |
| GET | `/health/ready` | Readiness probe (DB + S3 check in local; status-only in prod) |
| GET | `/health` | Alias for `/health/ready` |

---

## Database

### Entity Relationship Diagram

```mermaid
erDiagram
    users ||--o{ memberships : "joins groups"
    users ||--o{ refresh_tokens : "authenticates"
    users ||--o{ friendships : "connects"
    groups ||--o{ memberships : "has members"
    groups ||--o{ expenses : "tracks costs"
    groups ||--o{ shopping_sessions : "tracks shopping"
    groups ||--o{ settlement_batches : "settles debts"
    groups ||--o{ settlement_payments : "records payments"
    expenses ||--o{ expense_splits : "divided into"
    memberships ||--o{ expense_splits : "owes share"
    shopping_sessions ||--o{ shopping_items : "contains"
    shopping_sessions ||--o{ shopping_session_participants : "includes"
    shopping_sessions ||--|| receipt_uploads : "has receipt"
    shopping_items ||--o{ shopping_item_splits : "divided into"
    memberships ||--o{ shopping_item_splits : "shares cost"
    receipt_uploads ||--o{ receipt_extracted_items : "OCR output"

    users {
        uuid id PK
        string username "CI unique"
        string email "CI unique"
        string password_hash "bcrypt"
        string first_name
        string last_name
        timestamp created_at
    }
    groups {
        uuid id PK
        string name
        string currency "default USD"
        int version
        timestamp created_at
    }
    memberships {
        uuid id PK
        uuid group_id FK
        uuid user_id FK
        enum role "owner | member | viewer"
    }
    expenses {
        uuid id PK
        uuid group_id FK
        uuid paid_by FK
        bigint amount_cents "check > 0"
        string title
        date expense_date
    }
    expense_splits {
        uuid id PK
        uuid expense_id FK
        uuid membership_id FK
        bigint share_cents "check >= 0"
    }
    shopping_sessions {
        uuid id PK
        uuid group_id FK
        uuid paid_by_membership_id FK "composite FK"
        enum status "active | finalized | settled"
        date shopping_date
    }
    shopping_items {
        uuid id PK
        uuid session_id FK
        string name
        int quantity "check >= 1"
        bigint total_cents "check > 0"
    }
    shopping_item_splits {
        uuid id PK
        uuid item_id FK
        uuid membership_id FK
        bigint share_cents "check >= 0"
    }
    receipt_uploads {
        uuid id PK
        uuid session_id FK "unique"
        uuid uploaded_by_membership_id FK
        string storage_key
    }
    settlement_batches {
        uuid id PK
        uuid group_id FK
        enum status "suggested | paid | voided"
        int total_settlements
        int version
    }
    settlement_payments {
        uuid id PK
        uuid group_id FK
        uuid from_membership FK
        uuid to_membership FK
        bigint amount_cents "check > 0"
        enum status "pending | confirmed | voided"
    }
```

### 17 Tables

| Table | Key Constraints | Notes |
|-------|----------------|-------|
| `users` | CI unique on `username`, `email` | bcrypt password hash |
| `groups` | Optimistic locking via `version` | Default currency USD |
| `memberships` | Unique `(group_id, user_id)` | Role enum: owner/member/viewer |
| `expenses` | `amount_cents > 0` | Paid-by references membership |
| `expense_splits` | `share_cents >= 0` | One row per member per expense |
| `shopping_sessions` | Composite FK `(group_id, paid_by_membership_id)` | Status: active/finalized/settled |
| `shopping_items` | `quantity >= 1`, `total_cents > 0` | Linked to session |
| `shopping_item_splits` | `share_cents >= 0` | One row per sharer per item |
| `shopping_session_participants` | Unique `(session_id, membership_id)` | Participant list |
| `receipt_uploads` | Unique on `session_id` (one receipt per session) | S3 storage key |
| `receipt_extracted_items` | FK to receipt_upload | OCR results with confidence |
| `settlement_batches` | Versioned per group | Immutable snapshot of transfers |
| `settlements` | `from_membership != to_membership` | Individual transfer instructions |
| `settlement_payments` | `amount_cents > 0` | Pending/confirmed/voided lifecycle |
| `settlement_payment_sessions` | Bridge table | Links payments to shopping sessions |
| `refresh_tokens` | Unique `token_jti` | `replaced_by_jti` for rotation chain |
| `friendships` | Unique `(user_low_id, user_high_id)`, `low < high` | Status: pending/accepted/declined |
| `activity_log` | FK to group + user | Audit trail |
| `idempotency_keys` | Unique `(endpoint, user_id, idempotency_key)` | Cached response + status code |

### Migrations (Alembic)

14 revisions from `20241218_0001_initial` to `20260216_0014_idempotency_key_header_enforcement`. CI validates full upgrade/downgrade/upgrade cycle on every run.

---

## Request Lifecycle

```mermaid
sequenceDiagram
    participant C as Client
    participant U as Uvicorn
    participant MW as Middleware
    participant R as Router
    participant S as Service
    participant DB as PostgreSQL
    participant S3 as AWS S3

    C->>U: POST /groups/{id}/expenses<br/>Authorization: Bearer JWT<br/>Idempotency-Key: abc-123

    rect rgb(245, 245, 245)
        Note over U,MW: Middleware Pipeline
        U->>MW: CORS origin check
        MW->>MW: Inject security headers<br/>(X-Content-Type-Options, X-Frame-Options, HSTS)
    end

    U->>R: Route dispatch
    R->>R: Decode JWT (HS256)<br/>Extract user_id from sub claim
    R->>R: Check Idempotency-Key<br/>If seen + same payload → return cached 201

    R->>S: create_expense(user, group_id, payload)
    S->>DB: SELECT membership WHERE user_id AND group_id
    S->>DB: INSERT expense (amount_cents)
    S->>DB: INSERT expense_splits (equal-split, integer cents)
    S->>DB: Store idempotency response

    S-->>R: Expense object
    R-->>C: 201 Created + JSON

    Note over C,U: On 401 → client refreshes via POST /auth/refresh<br/>Old JTI revoked, new token pair issued
```

### Middleware Stack (applied in order)

| Layer | Behavior |
|-------|----------|
| **CORS** | Local: `localhost:3000`. Non-local: HTTPS-only origins, validated at startup |
| **Security Headers** | `nosniff`, `DENY`, `strict-origin-when-cross-origin`, HSTS (non-local) |
| **Validation Sanitizer** | Strips `input` field from 422 errors (prevents password leakage) |
| **Rate Limiter** | In-memory sliding window. Signup: 5/5min, Login: 10/60s, Refresh: 20/60s |
| **Idempotency** | `Idempotency-Key` header on POST. Same key + payload = cached response. Different payload = 409 |
| **JWT Auth** | HS256 decode, `token_type: "access"` claim enforced. Dependency-injected via `get_current_user` |

### Auth Flow

- **Access tokens**: JWT HS256, 15-min expiry, claims: `{sub, email, type, exp}`
- **Refresh tokens**: Persisted in DB with unique JTI, 30-day expiry
- **Rotation**: On refresh, old token gets `revoked_at` + `replaced_by_jti`; replay of revoked token returns 401
- **Passwords**: bcrypt with `gensalt()`; unknown users still run dummy verify (timing-safe)

### Financial Arithmetic

All money values stored as `bigint` cents. Equal splits use deterministic remainder distribution: splitting 1000 cents among 3 members yields `[334, 333, 333]` (payer absorbs the extra cent). No floating-point anywhere in the pipeline.

---

## Local Development

### Quick Start (Docker)

```bash
git clone <repo-url> && cd ClearSplit
cp .env.example .env
echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env

docker compose up --build
# API: http://localhost:8000
# Docs: http://localhost:8000/docs
```

`docker-compose.yml` runs PostgreSQL 16 + the API with live reload (volume-mounted `./backend`).

### Without Docker

```bash
cd backend
python3.11 -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt

# Requires PostgreSQL 16 running, DATABASE_URL set in .env
alembic upgrade head
make run          # uvicorn --reload on :8000
```

### Makefile Targets

| Target | Command |
|--------|---------|
| `make run` | `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000` |
| `make test` | `pytest` |
| `make migrate` | `alembic upgrade head` |
| `make ci-pr` | Lint + tests (no e2e, 78% coverage gate) |
| `make ci-main` | Lint + full test suite (80% coverage gate) |

### Environment Variables

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `ENV` | Yes | `local` | `local`, `test`, `staging`, `production` |
| `DATABASE_URL` | Yes | - | `postgresql+asyncpg://user:pass@host:5432/db` |
| `JWT_SECRET` | Yes | - | Min 32 chars. Generate: `openssl rand -hex 32` |
| `CORS_ORIGINS` | Staging/prod | - | Comma-separated HTTPS origins |
| `S3_BUCKET_NAME` | For receipts | - | AWS S3 bucket name |
| `AWS_REGION` | For receipts | `us-east-2` | S3 region |
| `DB_POOL_SIZE` | No | `10` | SQLAlchemy pool size |
| `DB_MAX_OVERFLOW` | No | `20` | Max overflow connections |

Full template: `.env.example`

### iOS Client

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
# Simulator → auto-connects to http://127.0.0.1:8000
# Device → set API_BASE_URL env var to Mac's LAN IP
```

Zero external dependencies. Actor-based auth coordinator deduplicates concurrent 401 refreshes. Keychain-backed token storage.

### Troubleshooting

| Issue | Fix |
|-------|-----|
| `JWT_SECRET must be at least 32 characters` | `openssl rand -hex 32` |
| Alembic migration fails | Verify PostgreSQL is running + `DATABASE_URL` is correct |
| Port 5432 in use | `lsof -i :5432` to find conflicting process |
| `CORS_ORIGINS must be configured` | Set `ENV=local` for dev |
| Rate limited in dev | Rate limiting disabled when `ENV=test` |

---

## Deployment & Operations

### Environments

| Env | Database | TLS | Docs | Config Source |
|-----|----------|-----|------|---------------|
| `local` | Docker Compose PG 16 | Off | `/docs` enabled | `.env` / `.env.local` |
| `test` | CI service container | Off | Enabled | Workflow env vars |
| `staging` | Azure PostgreSQL | Required | Disabled | GitHub Secrets + Vars |

### Staging Pipeline

Triggered on push to `staging` branch. Fully automated via GitHub Actions.

1. **Backend CI** — lint (Ruff), migration validation (upgrade/downgrade/upgrade), tests (80% coverage)
2. **Build** — Docker image pushed to Azure Container Registry, tagged `<sha>`
3. **Trivy Scan** — blocks on HIGH/CRITICAL vulnerabilities
4. **Migrate** — `migration_precheck.py` + `alembic upgrade head` run as ACA container job
5. **Deploy** — New ACA revision with `--revision-suffix sha-<short>`
6. **Health Check** — polls `/health/live` + `/health/ready` for up to 3 minutes
7. **Rollback** — on health failure, reverts to previous image automatically

Azure auth uses OIDC federation (no static credentials). Secrets injected as ACA secret references.

### CI Workflows

| Workflow | Trigger | What Runs |
|----------|---------|-----------|
| `ci.yml` | PR to main/develop | Lint + migrations + tests (78% coverage) |
| `ci.yml` | Push to staging | Full suite (80% coverage) + Docker archive |
| `deploy-staging.yml` | After CI success on staging | ACR push + Trivy + migrate + deploy + health check |
| `docker.yml` | Push to main | Docker build + GHCR push + Trivy |
| `security-scan.yml` | PR/push/weekly | TruffleHog + pip-audit + Bandit |
| `ios-pr-checks.yml` | PR (ios/ changes) | SwiftLint + build + unit tests |
| `ios-main-checks.yml` | Push to main (ios/) | Full tests + archive |

### Security Controls

| Control | Implementation |
|---------|---------------|
| JWT secret validation | Min 32 chars, checked at startup |
| Refresh token rotation | JTI tracking, `replaced_by_jti` audit chain |
| Timing-safe login | Dummy bcrypt for unknown users |
| Rate limiting | Sliding window on auth endpoints |
| DB TLS | Enforced in non-local envs; startup rejection on bad SSL config |
| CORS | HTTPS-only in non-local; validated at startup |
| Upload validation | Content type, 10MB size, 25MP pixel limit, decompression bomb guard |
| API docs exposure | `/docs` and `/redoc` disabled outside local/test |
| Secret handling | `pydantic.SecretStr`; never in repr or logs |

Full security model and incident response: [SECURITY.md](SECURITY.md)

---

## Repository Structure

```
.
├── backend/
│   ├── app/
│   │   ├── api/            # 6 route modules (auth, groups, expenses, settlements, shopping, friends)
│   │   ├── auth/           # JWT, bcrypt, dependencies, refresh token rotation
│   │   ├── core/           # Config, rate limiting, idempotency, identity normalization
│   │   ├── db/             # Async engine, TLS connection builder
│   │   ├── models/         # 17 SQLAlchemy ORM models
│   │   ├── schemas/        # Pydantic request/response models
│   │   ├── services/       # Business logic + authorization
│   │   └── tests/          # 143+ pytest tests (unit, integration, e2e)
│   ├── alembic/            # 14 migration revisions
│   ├── Dockerfile          # python:3.11-slim + tesseract
│   ├── Makefile            # run, test, lint, migrate
│   └── requirements.txt
├── ios/ClearSplit/         # SwiftUI client (MVVM, zero deps, Keychain auth)
├── .github/workflows/      # 6 CI/CD pipelines
├── scripts/                # Secret scanning, security verification
├── docker-compose.yml      # Local: PG 16 + API
└── .env.example            # Environment template
```
