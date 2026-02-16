# Backend Reference

## Service Summary

- Framework: FastAPI
- Data: PostgreSQL with async SQLAlchemy
- Migrations: Alembic
- Auth: JWT access + rotating refresh tokens
- Storage: S3-compatible object storage for receipt images
- OCR: Tesseract via `pytesseract`

## Environment Variables

The backend loads settings from `.env`, `.env.local`, `../.env`, and `../.env.local`.

Required:

- `ENV` (`local`, `test`, `staging`, `production`)
- `DATABASE_URL`
- `JWT_SECRET`
- `S3_BUCKET_NAME`

Common optional settings:

- `JWT_ALGORITHM` (default `HS256`)
- `ACCESS_TOKEN_EXPIRE_MINUTES` (default `15`)
- `REFRESH_TOKEN_EXPIRE_DAYS` (default `30`)
- `CORS_ORIGINS` (comma-separated)
- `TRUST_PROXY_HEADERS` (default `false`)
- `TRUSTED_PROXY_IPS` (comma-separated CIDRs/IPs)
- `RATE_LIMIT_MAX_KEYS` (default `10000`)
- `DB_POOL_SIZE`, `DB_MAX_OVERFLOW`, `DB_POOL_TIMEOUT_SECONDS`, `DB_POOL_RECYCLE_SECONDS`, `DB_CONNECT_TIMEOUT_SECONDS`
- `AWS_REGION` (default `us-east-2`)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `S3_PRESIGNED_GET_EXPIRE_SECONDS` (default `900`)
- `S3_PREFIX` (default `receipts`)
- `MAX_RECEIPT_BYTES` (default `10485760`)
- `MAX_RECEIPT_PIXELS` (default `25000000`)
- `MAX_OCR_CONCURRENCY` (default `2`)

### CORS behavior

- `local`/`test`: local origins are allowed automatically, credentials disabled.
- non-local: `CORS_ORIGINS` is mandatory and must be HTTPS origins only, credentials enabled.

## API Surface

All endpoints are prefixed exactly as shown below.

### Health

- `GET /health/live`
- `GET /health/ready`
- `GET /health`

### Auth

- `POST /auth/signup`
- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`

### Friends

- `POST /friends/requests`
- `POST /friends/requests/{friendship_id}/accept`
- `POST /friends/requests/{friendship_id}/decline`
- `GET /friends`
- `GET /friends/requests/incoming`
- `GET /friends/requests/outgoing`
- `DELETE /friends/{friendship_id}`

### Groups and membership

- `POST /groups`
- `GET /groups`
- `GET /groups/{group_id}`
- `DELETE /groups/{group_id}`
- `POST /groups/{group_id}/members/preview`
- `POST /groups/{group_id}/members`
- `GET /groups/{group_id}/members`

### Expenses

- `POST /groups/{group_id}/expenses`
- `GET /groups/{group_id}/expenses`
- `GET /expenses/{expense_id}`

### Balances and settlement

- `GET /groups/{group_id}/balances`
- `POST /groups/{group_id}/settlements/compute`
- `GET /groups/{group_id}/settlements/latest`
- `POST /groups/{group_id}/settlement-payments`
- `POST /settlement-payments/{payment_id}/confirm`
- `GET /groups/{group_id}/settlement-payments`
- `PATCH /settlements/{settlement_id}` (legacy compatibility path)

### Shopping, receipts, OCR

- `POST /groups/{group_id}/shopping-sessions`
- `GET /groups/{group_id}/shopping-sessions`
- `GET /shopping-sessions/{session_id}`
- `PATCH /shopping-sessions/{session_id}`
- `POST /shopping-sessions/{session_id}/finalize`
- `DELETE /shopping-sessions/{session_id}`
- `PUT /shopping-sessions/{session_id}/participants`
- `POST /shopping-sessions/{session_id}/receipt`
- `GET /receipts/{receipt_upload_id}/download-url`
- `DELETE /receipts/{receipt_upload_id}`
- `POST /receipts/{receipt_upload_id}/extract-items`
- `GET /receipts/{receipt_upload_id}/extracted-items`
- `POST /shopping-sessions/{session_id}/items`
- `PATCH /items/{item_id}`
- `DELETE /items/{item_id}`
- `PUT /items/{item_id}/sharers`

## Authorization Rules

### Role model

- `owner`: full group control (member management, payer-level actions, owner overrides)
- `member`: standard mutation rights based on endpoint-specific rules
- `viewer`: read-only for financial and shopping mutations

### Important endpoint rules

- Group deletion is owner-only.
- Member preview/add is owner-only.
- Expense creation requires non-viewer membership and `paid_by` must be caller membership.
- Shopping session creation requires non-viewer membership and payer must be caller membership.
- Participant updates/finalize/delete session are payer-only.
- Item update/delete/sharer-set is restricted to item creator, session payer, or group owner.
- Receipt upload is participant-only.
- Receipt delete and OCR extraction are uploader-only.
- Settlement payment creation is sender-or-owner.
- Settlement payment confirmation is receiver-or-owner.

## Idempotency

Supported mutation endpoints inspect optional `Idempotency-Key` headers:

- `POST /groups/{group_id}/expenses`
- `POST /groups/{group_id}/settlements/compute`

Behavior:
- same key + same payload returns cached response
- same key + different payload returns HTTP 409
- key length is capped at 255 characters

## Data Model (Primary Tables)

Identity and auth:
- `users`
- `refresh_tokens`
- `idempotency_keys`

Groups and social graph:
- `groups`
- `memberships`
- `friendships`

Expenses and settlement:
- `expenses`
- `expense_splits`
- `settlement_batches`
- `settlements`
- `settlement_payments`
- `settlement_payment_sessions`

Shopping and receipts:
- `shopping_sessions`
- `shopping_session_participants`
- `shopping_items`
- `shopping_item_splits`
- `receipt_uploads`
- `receipt_extracted_items`

## Operations

Install and run:

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
make run
```

Quality/test:

```bash
make lint-ci
make test
make test-pr
make test-all
```

## Notes for Integrators

- Monetary values are integer cents in API payloads unless explicitly named as decimal totals in shopping session metadata.
- Date parsing on client side should handle ISO timestamps with and without fractional seconds.
- OpenAPI/Swagger routes are intentionally enabled only in `local` and `test` environments.
