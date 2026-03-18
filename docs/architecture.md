# Architecture

## System Topology

```
┌──────────────┐      HTTPS/JSON       ┌──────────────────┐
│  iOS App     │ ◄──────────────────► │  FastAPI Backend  │
│  (SwiftUI)   │                       │  (Python 3.11)    │
└──────────────┘                       └──┬───────────────┘
                                          │
              ┌───────────────────────────┼───────────────────────────┐
              │                           │                           │
       ┌──────▼──────┐           ┌────────▼───────┐         ┌────────▼───────┐
       │ PostgreSQL  │           │  Redis 7        │         │ S3-Compatible  │
       │    16       │           │  (cache+broker) │         │   Storage      │
       └─────────────┘           └────────┬───────┘         └────────────────┘
                                          │
                                 ┌────────▼───────┐
                                 │ Celery Worker  │
                                 │ (Tesseract OCR)│
                                 └────────────────┘
```

- **iOS app** (SwiftUI, async/await) handles UI, local state, and Keychain token storage
- **FastAPI backend** exposes REST endpoints, enforces domain rules, manages auth
- **PostgreSQL 16** stores all relational data (20 tables, 15 migrations)
- **Redis 7** serves two roles: cache store for balance queries and Celery message broker
- **Celery worker** runs Tesseract OCR off the API process — same Docker image, different entrypoint
- **S3-compatible storage** stores receipt images with presigned URL access

## Request Lifecycle

1. iOS sends JSON or multipart request to FastAPI
2. Rate limiter checks client IP against configured limits (signup, login, preview)
3. Backend authenticates user from Bearer access token via `get_current_user` dependency
4. Route handler extracts and validates input via Pydantic schemas
5. Route delegates to service-layer function for business logic
6. Service enforces role-based permissions and domain invariants
7. SQLAlchemy async session persists/reads data from PostgreSQL
8. Response is serialized via Pydantic schemas and returned

## Backend Design Principles

- **Thin routes, thick services** — route handlers delegate to service functions; business logic never lives in route files
- **Role-aware permissions** — `owner`, `member`, `viewer` roles checked at service boundaries, not just route level
- **Deterministic split arithmetic** — integer cents with stable remainder distribution (payer-preferred, then UUID-sorted)
- **Idempotency support** — mutation endpoints accept `Idempotency-Key` header; replays return cached responses, payload mismatches return 409
- **Group-scoped integrity** — composite foreign keys ensure expenses, splits, settlements, and shopping items can only reference memberships within their own group
- **Async-first** — SQLAlchemy 2.0 async with asyncpg driver, async session management throughout
- **Deferred FK constraints** — settlement constraints are deferred to handle complex atomic operations within a single transaction

## Backend Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│  Route Handlers (app/api/)                          │
│  ─ HTTP input/output, schema validation             │
│  ─ Delegates to services, never contains logic      │
├─────────────────────────────────────────────────────┤
│  Service Layer (app/services/)                      │
│  ─ Business logic, authorization checks             │
│  ─ Domain invariant enforcement                     │
│  ─ Transaction orchestration                        │
├─────────────────────────────────────────────────────┤
│  Auth Layer (app/auth/)                             │
│  ─ JWT creation/validation, password hashing        │
│  ─ Refresh token rotation with JTI tracking         │
│  ─ FastAPI dependency injection for auth context     │
├─────────────────────────────────────────────────────┤
│  Core Utilities (app/core/)                         │
│  ─ Settings (Pydantic BaseSettings, SecretStr)      │
│  ─ Rate limiting (in-memory sliding window)         │
│  ─ Idempotency key management                       │
│  ─ Identity normalization (case-insensitive)        │
│  ─ Redis cache (singleton client, cache-aside helpers)│
├─────────────────────────────────────────────────────┤
│  Async Worker (app/worker/)                         │
│  ─ Celery app configured from Settings              │
│  ─ Sync SQLAlchemy session (psycopg2)               │
│  ─ run_receipt_ocr task with retry (max 2)          │
├─────────────────────────────────────────────────────┤
│  Data Layer                                         │
│  ─ Models (app/models/) — 20 SQLAlchemy ORM models  │
│  ─ Schemas (app/schemas/) — Pydantic DTOs           │
│  ─ Database (app/db/) — async session + TLS config  │
└─────────────────────────────────────────────────────┘
```

## Core Domain Flows

### Authentication

- Access tokens are short-lived JWTs (15 min, type: `access`)
- Refresh tokens include a unique JTI and are persisted in `refresh_tokens` table
- Refresh rotation: old token is revoked (`revoked_at` set, `replaced_by_jti` recorded), new token issued with fresh JTI
- Replaying a revoked refresh token returns 401
- Passwords hashed with bcrypt via `bcrypt.gensalt()`
- Timing-attack resistant: login always runs password verification (dummy hash for unknown users)

### Identity Normalization

- Emails and usernames are normalized to lowercase before storage and lookup
- Case-insensitive unique indices: `uq_users_email_ci` and `uq_users_username_ci` using `func.lower()`
- Login accepts either username or email as `identifier`, normalized before query

### Expense and Balance Computation

- Expenses record a payer (`paid_by` membership) and split obligations across members
- Equal split: `amount_cents / num_splits` with remainder distributed to first N members
- Live balance engine computes `net_cents = total_paid - total_owed` per membership
- Balance computation includes: expenses, shopping item splits, and confirmed settlement payments
- Transfer suggestions generated by greedy matching of debtors to creditors
- Results are cached in Redis under `balances:{group_id}:v1` (TTL 60s). Every endpoint that mutates group finances — expenses, shopping items, settlements — calls `invalidate_balances_cache()` after commit. Cache failure is silent; the endpoint falls through to a fresh DB query.

### Settlement Payments

- Payments can be **pending** (awaiting receiver confirmation) or **auto-confirmed**
- Confirmed payments feed back into live balance computation
- Payment can optionally link to shopping sessions via join table `settlement_payment_sessions`
- Settlement batches are immutable snapshots of computed transfers at a point in time
- Only status and void reason are mutable on batches (per ADR 0001)

### Shopping Sessions

- Session lifecycle: `active` → `finalized` → `settled`
- Financial mutations (item edit/delete) reopen `settled` sessions back to `active`
- Participant changes are managed by payer only
- Item sharers get deterministic equal splits with payer-preferred remainder assignment
- One receipt per session (enforced by unique constraint on `session_id`)
- Items can be created by any session participant; edit/delete restricted to creator, payer, or group owner

### Receipt and OCR Pipeline

Upload and extraction are two separate operations.

**Upload** (`POST /shopping-sessions/{id}/receipt`):
1. Validates content type, image format (JPEG/PNG/WEBP/GIF), file size (default 10 MB), pixel count (default 25 MP), decompression bomb
2. Stores image in S3 under `{s3_prefix}/{uuid}` key
3. Returns receipt upload ID — no OCR runs here

**Async extraction** (`POST /receipts/{id}/extract-items`):
1. Creates an `async_jobs` row with status `queued` (partial unique index prevents duplicate active jobs for the same receipt)
2. Returns HTTP 202 with `job_id` and `status_url` — responds in ~10 ms
3. Celery worker picks up the job: fetches bytes from S3, runs Tesseract, writes `receipt_extracted_items` rows, marks job `succeeded`
4. iOS polls `GET /jobs/{job_id}` until status is `succeeded` or `failed`, then fetches `GET /receipts/{id}/extracted-items`

If extracted items already exist when the endpoint is called, it returns them directly as HTTP 200 without enqueuing a new job.

The worker uses a synchronous SQLAlchemy session (psycopg2) — Celery tasks are synchronous Python, so the async session from the API process can't be reused.

### Friends

- Friend requests create a `friendships` row with `user_low_id < user_high_id` (normalized edge)
- Status lifecycle: `pending` → `accepted` or `declined`
- Reverse request on pending friendship auto-accepts
- Declined friendships can be re-sent
- Check constraints ensure: distinct users, requester is a participant

## Middleware Pipeline

Requests pass through these middleware layers in order:

1. **CORS Middleware** — origin validation (HTTPS-only in non-local environments)
2. **Security Headers Middleware** — adds protective headers:
   - `X-Content-Type-Options: nosniff`
   - `X-Frame-Options: DENY`
   - `Referrer-Policy: strict-origin-when-cross-origin`
   - `X-Permitted-Cross-Domain-Policies: none`
   - `Strict-Transport-Security` (non-local environments only, max-age=63072000)
3. **Metrics Middleware** — records `REQUEST_COUNT` and `REQUEST_LATENCY` Prometheus metrics per route and status code. Wraps the full request lifecycle (executes outermost due to FastAPI's reverse middleware ordering). No-ops when `PROMETHEUS_ENABLED=false`.
4. **Request Validation Error Handler** — sanitizes validation errors (removes raw input values from responses)

## iOS Architecture

### State Management

- `AppState` (`@MainActor ObservableObject`) is the single source of truth for all authenticated data
- Published dictionaries keyed by group ID: expenses, memberships, balances, shopping sessions, payments
- Bootstrap sequence: load Keychain tokens → verify session → fetch user → load groups

### Networking Layer

- `APIClient` singleton handles all HTTP communication (390 lines)
- `AuthCoordinator` (Swift actor) manages thread-safe token storage and de-duplicates concurrent refresh requests
- Automatic 401 retry: on unauthorized response, refreshes token and replays the original request once
- JSON key conversion: `convertFromSnakeCase` / `convertToSnakeCase`
- Date parsing supports multiple ISO-8601 formats including microsecond precision
- Multipart form-data support for receipt image uploads

### Service Layer

- Protocol-based services: `AuthServicing`, `GroupsServicing`, `ShoppingServicing`, `SettlementServicing`, `FriendsServicing`
- Each service wraps `APIClient.request()` calls with typed request/response models
- Protocol-based design enables easy mocking for unit tests

### Navigation

- Three-tab structure: **Groups**, **Friends**, **Profile**
- Groups tab: list → detail → shopping sessions / balances & settlements
- Shopping detail: participants → receipts → items → extracted items review
- Login/signup presented when unauthenticated
- Uses SwiftUI `NavigationStack` with conditional navigation and sheet/fullScreenCover modals

### Design System

- **Spacing**: xxs(4), xs(8), sm(12), md(16), lg(20), xl(24), xxl(32)
- **Radius**: sm(8), md(12), lg(16), xl(20), pill(999)
- **Typography**: hero, title, sectionTitle, body, bodyStrong, subheadline, footnote, caption
- **Colors**: brand palette (blue600), semantic colors (success/warning/danger), surface variants
- **Components**: 26 reusable components (cards, avatars, form elements, layout helpers, state views)

### Token Storage

- Keychain service with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- JSON-encoded `AuthTokens` struct (access, refresh, token type)
- Cleared on logout

## Security-Critical Behaviors

- Non-local environments require explicit HTTPS CORS origins (validated at startup)
- Trusted-proxy header handling is opt-in (`TRUST_PROXY_HEADERS=false` by default) with IP allowlist
- Rate limiting protects signup (5/5min), login (10/60s), and member preview (30/60s per group/user/IP)
- Rate limiting disabled in test environment; process-local only (each replica has own counters)
- Receipt processing defends against malformed/oversized image payloads
- Database TLS enforced by default in non-local environments
- Secrets use `SecretStr` in Pydantic config with accessor methods (never exposed in logs)
- Error responses are sanitized to prevent password/secret leakage
- API documentation endpoints disabled in non-local environments
