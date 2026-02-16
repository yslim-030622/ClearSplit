# ClearSplit

ClearSplit is a split-expense system for groups, with a FastAPI backend and a SwiftUI iOS client.

The repository contains:
- `backend/`: API, domain logic, migrations, tests
- `ios/ClearSplit/`: iOS app, networking layer, UI, and test scripts
- `docs/`: project documentation
- `scripts/`: security and operational helper scripts

## Product Scope (Current)

ClearSplit currently supports:
- user signup/login with JWT access + rotating refresh tokens
- group creation and membership roles (`owner`, `member`, `viewer`)
- invite preview and member add flows
- expense creation with equal splits
- live balances and settlement suggestions
- persisted settlement payments with sender/receiver confirmation flow
- shopping sessions, participants, item splits, and lifecycle (`active`, `finalized`, `settled`)
- receipt upload to S3-compatible storage
- receipt OCR extraction and item parsing
- friendship requests and friend list management

## Tech Stack

- Backend: Python, FastAPI, SQLAlchemy (async), PostgreSQL, Alembic
- Infra integrations: S3-compatible object storage, Tesseract OCR
- iOS: SwiftUI, URLSession, Keychain-based token storage

## Quick Start

### 1) Prerequisites

- Python 3.11+
- Docker and Docker Compose
- PostgreSQL (if running backend without Compose)
- Xcode 15+ (for iOS)

### 2) Backend via Docker Compose

From repo root:

```bash
docker compose up --build
```

This starts:
- `db` on `localhost:${POSTGRES_PORT:-5432}`
- `api` on `http://localhost:8000`

Health checks:
- `GET /health/live`
- `GET /health/ready`

### 3) Backend local workflow (without Compose)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
make run
```

### 4) iOS app

Open the Xcode project:

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```

By default, the app targets `http://127.0.0.1:8000`.
For real devices, set `API_BASE_URL` in app configuration to your Mac LAN IP (for example `http://192.168.x.x:8000`).

## Test and Quality Commands

Backend:

```bash
cd backend
make test
make lint-ci
make test-pr
```

iOS scripts:

```bash
cd ios/ClearSplit
./scripts/ios_build.sh
./scripts/ios_test.sh all
./scripts/ios_lint.sh
```

Security helpers:

```bash
./scripts/secret-scan.sh
./scripts/verify-security.sh
```

## Documentation

Start here:
- `docs/INDEX.md`

Core references:
- `docs/architecture.md`
- `docs/backend-reference.md`
- `docs/ios-reference.md`
- `docs/workflows-and-operations.md`
- `SECURITY.md`
