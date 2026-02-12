# Backend Reference

## Stack

- FastAPI application (`backend/app/main.py`)
- SQLAlchemy async ORM + PostgreSQL
- Alembic migrations
- Pydantic schemas
- JWT auth with bcrypt password hashing
- S3-backed receipt storage and OCR extraction

## Layered Structure

| Layer | Path | Responsibility |
| --- | --- | --- |
| API | `backend/app/api/` | Route handlers, request/response models, auth dependencies. |
| Services | `backend/app/services/` | Business rules and domain operations. |
| Models | `backend/app/models/` | SQLAlchemy table mappings and relationships. |
| Schemas | `backend/app/schemas/` | Input/output contract definitions. |
| Auth | `backend/app/auth/` | JWT handling, password hashing, current-user dependency. |
| Core | `backend/app/core/` | Settings and idempotency key utilities. |
| DB | `backend/app/db/` | Base metadata and async session factory. |

## API Surface

### Health

- `GET /health`

Checks API liveliness, DB query ability, and S3 configuration presence.

### Auth

- `POST /auth/signup`
- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`

### Groups and Memberships

- `POST /groups`
- `GET /groups`
- `GET /groups/{group_id}`
- `POST /groups/{group_id}/members/preview`
- `POST /groups/{group_id}/members`
- `GET /groups/{group_id}/members`

### Expenses

- `POST /groups/{group_id}/expenses`
- `GET /groups/{group_id}/expenses`
- `GET /expenses/{expense_id}`

Behavior:

- equal split creation
- deterministic remainder distribution
- optional idempotency replay using stored response payload
- settlement recomputation trigger after expense creation

### Settlements

- `POST /groups/{group_id}/settlements/compute`
- `GET /groups/{group_id}/settlements/latest`
- `PATCH /settlements/{settlement_id}`

Behavior:

- compute creates immutable batches
- only `status=paid` update supported via API
- only debtor membership can mark a settlement paid

### Shopping Sessions and Receipts

- `POST /groups/{group_id}/shopping-sessions`
- `GET /groups/{group_id}/shopping-sessions`
- `GET /shopping-sessions/{session_id}`
- `PATCH /shopping-sessions/{session_id}`
- `DELETE /shopping-sessions/{session_id}`
- `PUT /shopping-sessions/{session_id}/participants`
- `POST /shopping-sessions/{session_id}/receipt`
- `GET /receipts/{receipt_upload_id}/download-url`
- `DELETE /receipts/{receipt_upload_id}`
- `POST /shopping-sessions/{session_id}/items`
- `PATCH /items/{item_id}`
- `DELETE /items/{item_id}`
- `PUT /items/{item_id}/sharers`
- `POST /receipts/{receipt_upload_id}/extract-items`
- `GET /receipts/{receipt_upload_id}/extracted-items`

Key rules:

- payer-only operations for write actions affecting shopping, receipts, and sharers
- participants must remain compatible with existing item sharers
- OCR extraction endpoint is idempotent if extracted rows already exist

## Service Responsibilities

| Service | Core Responsibility |
| --- | --- |
| `group.py` | Membership checks, owner checks, group lookup/creation. |
| `membership.py` | User lookup by identifier and membership creation/listing. |
| `expense.py` | Equal split math, validation, expense creation/fetch, request hashing. |
| `settlement.py` | Balance aggregation and transfer generation algorithm. |
| `shopping.py` | Session/item/participant logic, S3 storage operations, sharer split generation. |
| `ocr.py` | OCR text extraction and heuristic line parsing into extracted items. |

## Data Model Overview

Primary entities:

- `users`
- `groups`
- `memberships`
- `expenses`
- `expense_splits`
- `settlement_batches`
- `settlements`
- `shopping_sessions`
- `shopping_session_participants`
- `shopping_items`
- `shopping_item_splits`
- `receipt_uploads`
- `receipt_extracted_items`
- `idempotency_keys`
- `activity_log`

Money representation:

- expense and settlement paths use integer cents (`BigInteger`)
- shopping items also use integer cents
- shopping session has optional `total_amount` numeric field for convenience summary

## Migration Timeline

| Revision | Purpose |
| --- | --- |
| `20241218_0001` | Core schema (users, groups, memberships, expenses, settlements, idempotency, activity). |
| `20250107_0002` | Shopping session, participant, receipt, item, item split tables. |
| `20250110_0003` | Add `shopping_sessions.total_amount`. |
| `20260127_0004` | Add `users.first_name` and `users.last_name`. |
| `20260128_0005` | Add `users.username` (CITEXT + index). |
| `20260209_0006` | Add `receipt_extracted_items` table. |

Canonical schema source is Alembic versions, not `backend/db/schema.sql`.

## Testing Coverage

Backend tests cover:

- auth endpoints and token handling
- group and membership permissions
- expense creation/splitting/idempotency
- settlement computation and paid-status authorization
- shopping session, receipt upload, sharers, OCR extraction flow
- core model persistence behaviors

Test locations:

- `backend/app/tests/`

## Operational Notes

- `backend/Dockerfile` installs Tesseract system packages for OCR.
- S3 credentials and bucket config are required for receipt flows.
- Some helper scripts in `backend/` reflect earlier payload formats and should be validated before relying on them in production workflows.
