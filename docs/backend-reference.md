# Backend Reference

## Service Summary

- **Framework**: FastAPI 0.122.0 with Uvicorn 0.30.1
- **Data**: PostgreSQL 16 with async SQLAlchemy 2.0+ (asyncpg driver)
- **Migrations**: Alembic 1.13.1 (14 migrations)
- **Auth**: JWT access + rotating refresh tokens with bcrypt password hashing
- **Storage**: S3-compatible object storage for receipt images
- **OCR**: Tesseract via `pytesseract` + Pillow
- **Entry point**: `backend/app/main.py`

## Environment Variables

The backend loads settings from `.env`, `.env.local`, `../.env`, and `../.env.local` via Pydantic `BaseSettings`.

### Required

| Variable | Description |
|----------|-------------|
| `ENV` | Environment: `local`, `test`, `staging`, `production` |
| `DATABASE_URL` | PostgreSQL connection string (must use `postgresql+asyncpg://` driver) |
| `JWT_SECRET` | Secret key for JWT signing (minimum 32 characters) |
| `S3_BUCKET_NAME` | AWS S3 bucket for receipt storage |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `JWT_ALGORITHM` | `HS256` | JWT signing algorithm |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `15` | Access token lifetime |
| `REFRESH_TOKEN_EXPIRE_DAYS` | `30` | Refresh token lifetime |
| `CORS_ORIGINS` | — | Comma-separated allowed origins (required for non-local) |
| `TRUST_PROXY_HEADERS` | `false` | Enable X-Forwarded-For parsing |
| `TRUSTED_PROXY_IPS` | — | Comma-separated CIDRs/IPs for proxy validation |
| `RATE_LIMIT_MAX_KEYS` | `10000` | Max tracked rate limit keys |
| `DB_POOL_SIZE` | `10` | SQLAlchemy connection pool size |
| `DB_MAX_OVERFLOW` | `20` | Max overflow connections |
| `DB_POOL_TIMEOUT_SECONDS` | `30` | Pool checkout timeout |
| `DB_POOL_RECYCLE_SECONDS` | `1800` | Connection recycle interval |
| `DB_CONNECT_TIMEOUT_SECONDS` | `10` | Connection establishment timeout |
| `AWS_REGION` | `us-east-2` | AWS region for S3 |
| `AWS_ACCESS_KEY_ID` | — | AWS credentials (optional with IAM roles) |
| `AWS_SECRET_ACCESS_KEY` | — | AWS credentials (optional with IAM roles) |
| `S3_PRESIGNED_GET_EXPIRE_SECONDS` | `900` | Presigned URL expiry (15 min) |
| `S3_PREFIX` | `receipts` | S3 key prefix for receipts |
| `MAX_RECEIPT_BYTES` | `10485760` | Max receipt file size (10 MB) |
| `MAX_RECEIPT_PIXELS` | `25000000` | Max image pixel count (25M) |
| `MAX_OCR_CONCURRENCY` | `2` | Concurrent OCR requests |

### CORS Behavior

- `local`/`test`: local origins allowed automatically, credentials disabled
- Non-local: `CORS_ORIGINS` is mandatory and must be HTTPS origins only, credentials enabled
- Invalid origin formats are rejected at app startup

### Environment-Specific Behaviors

| Setting | Local/Test | Staging/Production |
|---------|------------|-------------------|
| API docs (`/docs`, `/redoc`) | Enabled | Disabled |
| HSTS header | Not sent | Sent (63-day max-age) |
| CORS validation | Lenient | Strict HTTPS only |
| DB TLS | Optional | Enforced by default |

## API Surface

All endpoints return JSON. Authenticated endpoints require `Authorization: Bearer <token>`.

### Health

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/health/live` | No | Process liveness probe |
| GET | `/health/ready` | No | Dependency readiness (DB connectivity, returns 503 when degraded) |
| GET | `/health` | No | Backward-compatible alias of readiness |

### Auth

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| POST | `/auth/signup` | No | 5/5min per IP | Register new user |
| POST | `/auth/login` | No | 10/60s per IP | Authenticate (accepts username or email) |
| POST | `/auth/refresh` | No | — | Rotate refresh token (JTI-based) |
| GET | `/auth/me` | Yes | — | Current user profile |

**Auth response**: Returns `access_token`, `refresh_token`, `token_type` ("bearer"), and user info.

### Friends

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/friends/requests` | Yes | Send friend request (by user ID, username, or email) |
| POST | `/friends/requests/{friendship_id}/accept` | Yes | Accept pending request |
| POST | `/friends/requests/{friendship_id}/decline` | Yes | Decline pending request |
| GET | `/friends` | Yes | List accepted friends |
| GET | `/friends/requests/incoming` | Yes | Pending incoming requests |
| GET | `/friends/requests/outgoing` | Yes | Pending outgoing requests |
| DELETE | `/friends/{friendship_id}` | Yes | Remove friendship |

### Groups and Membership

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups` | Yes | Create group (creator becomes owner) |
| GET | `/groups` | Yes | List user's groups with membership ID |
| GET | `/groups/{group_id}` | Yes | Group details (requires membership) |
| DELETE | `/groups/{group_id}` | Yes | Delete group (owner only, cascades all data) |
| POST | `/groups/{group_id}/members/preview` | Yes | Preview user before adding (owner only, rate limited 30/60s) |
| POST | `/groups/{group_id}/members` | Yes | Add member to group (owner only) |
| GET | `/groups/{group_id}/members` | Yes | List group members |

### Expenses

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups/{group_id}/expenses` | Yes | Create expense with equal splits (idempotent via `Idempotency-Key`) |
| GET | `/groups/{group_id}/expenses` | Yes | List group expenses |
| GET | `/expenses/{expense_id}` | Yes | Get single expense by ID |

### Balances and Settlements

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/groups/{group_id}/balances` | Yes | Live balances + transfer suggestions |
| POST | `/groups/{group_id}/settlements/compute` | Yes | Compute settlement batch (idempotent) |
| GET | `/groups/{group_id}/settlements/latest` | Yes | Latest settlement batch |
| POST | `/groups/{group_id}/settlement-payments` | Yes | Create payment (pending or auto-confirmed) |
| POST | `/settlement-payments/{payment_id}/confirm` | Yes | Confirm pending payment |
| GET | `/groups/{group_id}/settlement-payments` | Yes | Payment history |
| PATCH | `/settlements/{settlement_id}` | Yes | Legacy compatibility (status=paid only) |

### Shopping Sessions

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups/{group_id}/shopping-sessions` | Yes | Create session |
| GET | `/groups/{group_id}/shopping-sessions` | Yes | List sessions |
| GET | `/shopping-sessions/{session_id}` | Yes | Session details with items/participants |
| PATCH | `/shopping-sessions/{session_id}` | Yes | Update session (payer only) |
| POST | `/shopping-sessions/{session_id}/finalize` | Yes | Finalize session (payer only) |
| DELETE | `/shopping-sessions/{session_id}` | Yes | Delete session (payer only, cascades) |
| PUT | `/shopping-sessions/{session_id}/participants` | Yes | Set participants (payer only) |

### Shopping Items

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/shopping-sessions/{session_id}/items` | Yes | Create item (participants only) |
| PATCH | `/items/{item_id}` | Yes | Update item (creator/payer/owner) |
| DELETE | `/items/{item_id}` | Yes | Delete item (creator/payer/owner) |
| PUT | `/items/{item_id}/sharers` | Yes | Set sharers with deterministic equal splits |

### Receipts and OCR

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/shopping-sessions/{session_id}/receipt` | Yes | Upload receipt image (participants only) |
| GET | `/receipts/{receipt_upload_id}/download-url` | Yes | Get presigned S3 download URL |
| DELETE | `/receipts/{receipt_upload_id}` | Yes | Delete receipt (uploader only) |
| POST | `/receipts/{receipt_upload_id}/extract-items` | Yes | Trigger OCR extraction (uploader only) |
| GET | `/receipts/{receipt_upload_id}/extracted-items` | Yes | View extracted items |

## Authorization Rules

### Role Model

| Role | Permissions |
|------|------------|
| `owner` | Full group control — member management, payer-level actions, owner overrides |
| `member` | Standard mutation rights based on endpoint-specific rules |
| `viewer` | Read-only for financial and shopping mutations |

### Endpoint Rules Summary

| Action | Allowed By |
|--------|-----------|
| Group deletion | Owner only |
| Member preview/add | Owner only |
| Expense creation | Non-viewer, `paid_by` must be caller's membership |
| Shopping session creation | Non-viewer, payer must be caller's membership |
| Participant updates / finalize / delete session | Payer only |
| Item update / delete / set sharers | Item creator, session payer, or group owner |
| Receipt upload | Session participants only |
| Receipt delete / OCR extraction | Uploader only |
| Settlement payment creation | Sender or owner |
| Settlement payment confirmation | Receiver or owner |

## Idempotency

Supported mutation endpoints inspect optional `Idempotency-Key` headers:

- `POST /groups/{group_id}/expenses`
- `POST /groups/{group_id}/settlements/compute`

Behavior:
- Same key + same payload → returns cached response
- Same key + different payload → returns HTTP 409
- Key length capped at 255 characters
- Scope: endpoint + user ID + key value

## Data Model (18 Tables)

### Identity and Auth
- `users` — account records with case-insensitive email/username indices
- `refresh_tokens` — JTI-tracked tokens for rotation and replay prevention
- `idempotency_keys` — request deduplication (endpoint, user_id, key, request_hash)

### Groups and Social Graph
- `groups` — expense groups with name, currency, version tracking
- `memberships` — user-group links with role enum (owner/member/viewer)
- `friendships` — normalized bidirectional edges (user_low_id < user_high_id)

### Expenses and Settlement
- `expenses` — expense records with payer, amount_cents, currency, date, memo
- `expense_splits` — per-member share with composite group FK
- `settlement_batches` — immutable snapshots (suggested/paid/voided)
- `settlements` — individual transfer instructions within batches
- `settlement_payments` — actual payment records (pending/confirmed/voided)
- `settlement_payment_sessions` — links payments to shopping sessions

### Shopping and Receipts
- `shopping_sessions` — grocery trips with lifecycle status
- `shopping_session_participants` — members in a session
- `shopping_items` — line items with name, quantity, unit_price_cents, total_cents
- `shopping_item_splits` — per-sharer allocation with SUM invariant
- `receipt_uploads` — S3 storage metadata with content type
- `receipt_extracted_items` — OCR-extracted data with confidence scores

### Activity
- `activity_logs` — audit trail for group activities

## Migrations

14 Alembic migrations (December 2024 – February 2026):

| Migration | Description |
|-----------|-------------|
| 0001 | Initial schema (users, groups, memberships, expenses, splits, settlements) |
| 0002 | Shopping tables (sessions, participants, items, splits, receipts) |
| 0003 | Add total_amount to shopping sessions |
| 0004 | Add first/last name to users |
| 0005 | Add username to users |
| 0006 | Receipt extracted items table |
| 0007 | Balances and settlement payments |
| 0008 | Receipt uploader permissions |
| 0009 | Refresh token rotation |
| 0010 | Shopping membership integrity (composite FKs) |
| 0011 | Friendships table |
| 0012 | Remove extension dependencies (uuid-ossp) |
| 0013 | Case-insensitive user identity uniqueness |
| 0014 | Idempotency key header enforcement |

## Operations

### Install and Run

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
make run
```

### Quality and Testing

```bash
make lint-ci          # Ruff linting
make test             # Full test suite
make test-pr          # PR gate (no e2e, 80% coverage)
make test-all         # Main gate (with e2e, 80% coverage)
make ci-pr            # Lint + PR tests
make ci-main          # Lint + all tests (main push release gate)
```

### Migration Management

```bash
alembic upgrade head          # Apply all pending migrations
alembic downgrade -1          # Rollback one migration
alembic revision --autogenerate -m "description"  # Generate new migration
```

Migration precheck script for deployments: `backend/app/scripts/migration_precheck.py`

## Notes for Integrators

- Monetary values are integer cents in API payloads unless explicitly named as decimal totals in shopping session metadata
- Date parsing on client side should handle ISO timestamps with and without fractional seconds
- OpenAPI/Swagger routes are intentionally enabled only in `local` and `test` environments
- All UUIDs in the API are v4 format
- Responses use snake_case JSON keys
