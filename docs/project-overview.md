# Project Overview

## What ClearSplit Is

ClearSplit is a two-client system:

- a FastAPI backend that owns business rules and persistence
- a SwiftUI iOS app that handles authentication, group operations, shopping flows, and receipt review

The practical product focus is itemized shopping split workflows, while classic group expense and settlement flows remain available.

## System Shape

### Backend (`backend/`)

- Framework: FastAPI + SQLAlchemy async + Alembic
- Database: PostgreSQL
- Auth: JWT access + refresh token model
- Storage: S3 for receipt images
- OCR: Tesseract pipeline for extracted receipt line items

### iOS (`ios/`)

- UI: SwiftUI
- Pattern: MVVM with `AppState` as top-level state container
- Networking: custom `APIClient` with token refresh + retry on `401`
- Secure storage: Keychain for tokens

### Infra and Automation

- Docker Compose local stack: API + Postgres
- GitHub Actions for CI, security scanning, Docker publish, and staging deployment template

## Core Runtime Flows

### 1) Authentication

1. iOS sends login/signup request.
2. Backend validates user and returns tokens.
3. iOS stores tokens in Keychain.
4. Protected requests include Bearer access token.
5. On `401`, iOS refreshes access token and retries once.

### 2) Group Expenses and Settlements

1. User creates group and memberships.
2. Expense is created with equal split logic.
3. Split shares are persisted atomically with the expense.
4. Settlement batch can be computed from net balances.
5. Only debtor membership can mark settlement as paid.

### 3) Shopping Sessions + Receipts + OCR

1. User creates shopping session for a group.
2. Payer defines participants.
3. Payer uploads receipt image (stored in S3, referenced in DB).
4. Payer triggers OCR extraction for line items.
5. Extracted items are reviewed and confirmed into shopping items.
6. Sharers are set per item; equal split shares are generated deterministically.

## Data and Consistency Rules

- Expense and settlement money values are modeled in integer cents.
- Equal split remainder is deterministic (extra cents assigned in stable order).
- Settlement batches are immutable snapshots (new compute creates a new batch).
- Write endpoints support idempotency storage for request deduplication.
- Timestamps are emitted as ISO-8601 and decoded in iOS with tolerant parsing.

## Current Repository Reality

- `web/` is currently a placeholder (`web/src/` exists but no active implementation).
- iOS has an active Swift package source tree (`ios/ClearSplit/Sources/ClearSplit`) and a minimal app-template residue under `ios/ClearSplit/ClearSplit/ClearSplit/ContentView.swift`.
- Existing docs include both active and legacy content; use `docs/INDEX.md` for the current set.
