# Project Overview

## What ClearSplit Is

ClearSplit is a split-expense management system with a **FastAPI backend** and a **SwiftUI iOS client**. It helps groups of people track shared expenses and shopping sessions, then settle up with the smallest practical number of transfers.

Two core user experiences:

1. **Expense tracking** — enter shared expenses, see live per-member balances, and get settlement suggestions
2. **Shopping sessions** — collaborative shopping with receipt upload, OCR-assisted item entry, and per-item split assignment

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11, FastAPI 0.122.0, SQLAlchemy 2.0 (async), Alembic |
| Database | PostgreSQL 16 via asyncpg |
| Auth | JWT (PyJWT) + bcrypt, refresh token rotation with JTI |
| Storage | S3-compatible object storage (boto3) for receipt images |
| OCR | Tesseract via pytesseract + Pillow for image processing |
| iOS | Swift 5.9, SwiftUI, iOS 16+, async/await |
| CI/CD | GitHub Actions, Docker, Azure Container Apps (staging) |
| Security scanning | TruffleHog, pip-audit, Bandit |

## Current Feature Set

### Accounts and Identity

- Signup with `username`, `email`, `password`, `first_name`, `last_name`
- Login using either username or email as the `identifier`
- JWT access tokens (15-minute expiry) with rotating refresh tokens (30-day expiry, JTI-tracked)
- Case-insensitive email and username matching via normalized lowercase indices
- Rate limiting on signup (5/5min) and login (10/60s)

### Groups and Membership

- Create, list, and delete groups
- Three roles: **owner** (full admin), **member** (read/write), **viewer** (read-only)
- Owner-only member management (add by username, email, or user ID)
- Invite preview endpoint to check user existence and membership status before adding
- Rate limiting on member preview (30/60s)

### Expenses and Balances

- Create expenses with equal-split distribution (deterministic remainder handling)
- Per-group expense history with splits
- Live group balance computation from expenses, shopping sessions, and confirmed payments
- Settlement suggestions via greedy transfer minimization algorithm
- Idempotency support on expense creation via `Idempotency-Key` header

### Settlement Payments

- Create pending or auto-confirmed settlement payments between members
- Receiver confirmation workflow
- Payment history per group
- Optional linking of payments to shopping sessions
- Settlement batch computation with idempotency support

### Shopping Sessions

- Create and manage shopping sessions within a group
- Configure participants per session
- Add, edit, and delete items with flexible pricing (unit price or total)
- Assign item sharers with deterministic equal-split remainder handling (payer-preferred)
- Session lifecycle: **active** → **finalized** → **settled**
- Payer-only session management (edit, delete, set participants)

### Receipts and OCR

- One receipt per shopping session (enforced by unique constraint)
- Participant-only receipt upload with image validation (format, size, pixel limits, decompression bomb protection)
- Uploader-only receipt deletion and OCR trigger
- OCR extraction with concurrency cap (default 2) and timeout
- Extracted items stored with raw OCR line and confidence score
- Review and import extracted items into the session

### Friends

- Send friend requests by user ID, username, or email
- Accept, decline, and remove friendships
- Incoming and outgoing request lists
- Friend list with search/filter
- Normalized bidirectional edge storage (lower UUID always first)
- Reverse pending request auto-accepts

## iOS App

- MVVM architecture with SwiftUI and async/await
- Three-tab navigation: Groups, Friends, Profile
- Keychain-based token storage (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- Actor-based token refresh coordination (de-duplicates concurrent refreshes)
- Camera and photo library receipt capture with JPEG compression
- Local balance calculation and settlement optimization
- Pull-to-refresh on all list views
- Custom design system with consistent spacing, typography, and color palette
- Zero external SPM dependencies

## Non-Goals (Current)

- No push notification pipeline
- No web client
- No background job queue for OCR (runs in request lifecycle with timeout)
- No multi-currency conversion in the settlement engine
- No certificate pinning on iOS (relies on default ATS)
