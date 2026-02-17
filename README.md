# ClearSplit

ClearSplit is a full-stack expense-splitting platform built for groups of people (roommates, friends, travel companions) who share costs. It pairs a **Python FastAPI backend** with a **SwiftUI iOS client** to track shared expenses, manage collaborative shopping sessions with receipt OCR, and settle debts with the fewest transfers possible.

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture Overview](#architecture-overview)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Running Tests](#running-tests)
- [CI/CD Pipelines](#cicd-pipelines)
- [Security](#security)
- [API Overview](#api-overview)
- [Documentation](#documentation)

## Features

### Accounts and Authentication
- Sign up with username, email, password, and name
- Log in with either username or email
- JWT access tokens (15-min expiry) with rotating refresh tokens (30-day expiry, JTI-tracked)
- Case-insensitive identity matching (email and username)
- Rate limiting on authentication endpoints

### Groups and Membership
- Create and manage expense groups
- Three roles: **owner** (full admin), **member** (read/write), **viewer** (read-only)
- Owner-only member management with invite preview before adding
- Members searchable by username, email, or user ID

### Expense Tracking and Balances
- Create expenses with automatic equal-split distribution
- Deterministic remainder handling (integer cents, no floating-point)
- Live per-member balance computation across expenses, shopping sessions, and confirmed payments
- Settlement suggestions via greedy transfer minimization
- Idempotency support via `Idempotency-Key` header

### Settlement Payments
- Record pending or auto-confirmed payments between members
- Receiver confirmation workflow
- Payment history per group with optional shopping session linking
- Immutable settlement batch snapshots for audit

### Shopping Sessions
- Create collaborative shopping trips within a group
- Configure session participants from group members
- Add, edit, and delete items with flexible pricing (unit price or total)
- Assign per-item sharers with deterministic equal-split remainder handling
- Session lifecycle: **active** → **finalized** → **settled**
- Payer-controlled session management

### Receipts and OCR
- Upload receipt images (JPEG, PNG, WEBP, GIF) with validation
- Private S3 storage with time-limited presigned download URLs
- Server-side Tesseract OCR extraction with concurrency limits
- Extracted items stored with raw OCR text and confidence scores
- Review and import extracted items into shopping sessions

### Friends
- Send friend requests by username, email, or user ID
- Accept, decline, and remove friendships
- Reverse pending request auto-accepts
- Incoming/outgoing request lists

### iOS App
- Native SwiftUI with MVVM architecture and async/await
- Three-tab navigation: Groups, Friends, Profile
- Keychain-based secure token storage
- Actor-based token refresh coordination (deduplicates concurrent refreshes)
- Camera and photo library receipt capture
- Custom design system with consistent spacing, typography, and color palette
- Zero external dependencies (pure Foundation + SwiftUI)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Backend** | Python 3.11, FastAPI 0.122.0, Uvicorn |
| **ORM & Database** | SQLAlchemy 2.0 (async), PostgreSQL 16, asyncpg, Alembic |
| **Authentication** | JWT (PyJWT) + bcrypt, refresh token rotation with JTI |
| **Object Storage** | S3-compatible storage (boto3) for receipt images |
| **OCR** | Tesseract via pytesseract + Pillow |
| **iOS** | Swift 5.9+, SwiftUI, iOS 16+, URLSession, Keychain |
| **CI/CD** | GitHub Actions (7 workflows), Docker, Fastlane |
| **Deployment** | Azure Container Apps (staging), GHCR (Docker images) |
| **Security Scanning** | TruffleHog, pip-audit, Bandit, Trivy |

## Architecture Overview

```
┌──────────────┐      HTTPS / JSON      ┌──────────────────┐
│  iOS App     │ ◄──────────────────►   │  FastAPI Backend  │
│  (SwiftUI)   │                        │  (Python 3.11)    │
└──────────────┘                        └────────┬─────────┘
                                                 │
                         ┌───────────────────────┼───────────────────────┐
                         │                       │                       │
                  ┌──────▼──────┐      ┌────────▼────────┐    ┌────────▼────────┐
                  │ PostgreSQL  │      │ S3-Compatible    │    │   Tesseract     │
                  │     16      │      │   Storage        │    │     OCR         │
                  └─────────────┘      └─────────────────┘    └─────────────────┘
```

**Key design principles:**

- **Thin routes, thick services** — business logic lives in the service layer, not route handlers
- **Role-aware permissions** — `owner`/`member`/`viewer` checked at service boundaries
- **Deterministic split arithmetic** — integer cents with stable remainder distribution
- **Idempotency support** — mutation endpoints accept `Idempotency-Key` header for safe retries
- **Group-scoped integrity** — composite foreign keys ensure cross-group references are impossible
- **Async-first** — SQLAlchemy 2.0 async with asyncpg throughout

## Repository Structure

```
.
├── backend/                    # FastAPI Python backend
│   ├── app/
│   │   ├── api/                #   Route handlers (auth, groups, expenses, settlements, shopping, friends)
│   │   ├── auth/               #   JWT, password hashing, refresh token rotation
│   │   ├── core/               #   Settings, rate limiting, idempotency, identity normalization
│   │   ├── db/                 #   SQLAlchemy engine/session, TLS connection handling
│   │   ├── models/             #   18 SQLAlchemy ORM models
│   │   ├── schemas/            #   Pydantic request/response schemas
│   │   ├── services/           #   Business logic and authorization rules
│   │   └── tests/              #   143+ tests (auth, groups, expenses, settlements, shopping, OCR, security)
│   ├── alembic/                #   14 database migrations (Dec 2024 – Feb 2026)
│   ├── Dockerfile              #   Python 3.11-slim + Tesseract OCR
│   ├── Makefile                #   Dev commands (run, test, lint, migrate)
│   └── requirements.txt        #   23 production dependencies
│
├── ios/ClearSplit/             # SwiftUI iOS client
│   ├── Sources/ClearSplit/
│   │   ├── State/              #   AppState (central coordinator, 438 lines)
│   │   ├── Networking/         #   APIClient + 5 domain services
│   │   ├── Models/             #   Codable data models
│   │   ├── ViewModels/         #   7 screen-level view models
│   │   ├── Views/              #   44 view files + 26 reusable components
│   │   ├── DesignSystem/       #   Colors, spacing tokens, button/card styles
│   │   └── Storage/            #   KeychainService for secure token persistence
│   ├── Tests/                  #   Unit tests (XCTest)
│   ├── scripts/                #   Build, test, lint, archive scripts
│   ├── fastlane/               #   Fastlane lanes for CI/CD
│   └── Package.swift           #   SPM manifest (iOS 16+, zero external deps)
│
├── docs/                       # Project documentation
│   ├── INDEX.md                #   Documentation entry point
│   ├── architecture.md         #   System design and data flows
│   ├── backend-reference.md    #   API endpoints, models, auth, config
│   ├── ios-reference.md        #   App architecture, networking, navigation
│   ├── project-overview.md     #   Product scope and feature set
│   ├── repository-map.md       #   Directory layout reference
│   ├── workflows-and-operations.md  # Dev workflow, testing, CI/CD, deployment
│   ├── dependencies.md         #   Runtime and dev dependencies
│   ├── features/               #   Feature specs (shopping model, receipt OCR)
│   ├── backend-docs/           #   Backend implementation details
│   └── adr/                    #   Architecture Decision Records
│
├── scripts/                    # Repo-level utility scripts
│   ├── secret-scan.sh          #   Secret detection in source files
│   ├── verify-security.sh      #   Security baseline verification
│   └── s3_smoke_test.py        #   S3 connectivity validation
│
├── .github/workflows/          # 7 CI/CD pipelines
├── docker-compose.yml          # Local dev: PostgreSQL 16 + API
├── .pre-commit-config.yaml     # Pre-commit hooks (ruff, secrets, formatting)
├── .env.example                # Environment variable template
└── SECURITY.md                 # Security model and incident response
```

## Getting Started

### Prerequisites

- Python 3.11+
- Docker and Docker Compose
- PostgreSQL 16 (if running backend without Compose)
- Xcode 15+ (for iOS development)
- SwiftLint (`brew install swiftlint`) for iOS linting

### Backend with Docker Compose (recommended)

From the repo root:

```bash
# Copy and configure environment variables
cp .env.example .env
# Edit .env with your settings (JWT_SECRET, etc.)

# Start PostgreSQL + API
docker compose up --build
```

This starts:
- `db` on `localhost:${POSTGRES_PORT:-5432}` (PostgreSQL 16)
- `api` on `http://localhost:8000` (FastAPI with live reload)

To use an external PostgreSQL (e.g., AWS RDS):

```bash
export API_DATABASE_URL='postgresql+asyncpg://<user>:<password>@<host>:5432/<db>?ssl=require'
docker compose up --build
```

Health check endpoints:
- `GET /health/live` — process liveness
- `GET /health/ready` — dependency readiness (DB connectivity)

### Backend without Docker

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt

# Apply database migrations
alembic upgrade head

# Start dev server with auto-reload
make run
```

### iOS App

```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```

- **Simulator**: uses `http://127.0.0.1:8000` by default
- **Physical device**: set `API_BASE_URL` in your Xcode scheme environment variables to your Mac's LAN IP (e.g., `http://192.168.x.x:8000`)

API base URL resolution order:
1. Xcode scheme environment variable `API_BASE_URL`
2. Info.plist `API_BASE_URL` key
3. Default: `http://127.0.0.1:8000`

## Running Tests

### Backend

```bash
cd backend

# Run full test suite
make test

# PR-equivalent (no e2e, 78% coverage minimum)
make test-pr

# Staging-equivalent (full suite, 80% coverage minimum)
make test-all

# Linting only
make lint-ci

# Full PR gate (lint + tests)
make ci-pr

# Full staging gate (lint + all tests)
make ci-main
```

**Test coverage**: 143+ tests across 13 test files covering auth, groups, expenses, settlements, shopping (51 tests), friends, security, OCR, rate limiting, and an end-to-end smoke test.

### iOS

```bash
cd ios/ClearSplit

# Build
./scripts/ios_build.sh

# Unit tests
./scripts/ios_test.sh unit

# UI smoke tests
./scripts/ios_test.sh ui

# All tests
./scripts/ios_test.sh all

# Lint
./scripts/ios_lint.sh
```

Or via Fastlane:

```bash
cd ios/ClearSplit
bundle install
bundle exec fastlane ios ci_pr     # PR gate: lint + build + unit tests
bundle exec fastlane ios ci_main   # Main gate: lint + build + all tests + archive
```

### Security Checks

```bash
# Scan for hardcoded secrets in source files
./scripts/secret-scan.sh

# Verify security baseline (gitignore, env files, secret types)
./scripts/verify-security.sh

# S3 connectivity smoke test
python scripts/s3_smoke_test.py
```

### Pre-commit Hooks

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

Hooks include: trailing whitespace, merge conflict detection, ruff Python linting, and custom secret scanning.

## CI/CD Pipelines

Seven GitHub Actions workflows automate testing, building, security scanning, and deployment:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **Backend CI** (`ci.yml`) | PRs, staging push | Lint, migration validation, tests (78% PR / 80% staging) |
| **Docker Build** (`docker.yml`) | Push to main, `v*` tags | Build and push to GHCR with Trivy security scan |
| **iOS PR Checks** (`ios-pr-checks.yml`) | PRs | SwiftLint + simulator build + unit tests |
| **iOS Main Checks** (`ios-main-checks.yml`) | Push to main | Full validation + optional TestFlight upload |
| **Security Scan** (`security-scan.yml`) | PRs, push, weekly | TruffleHog + pip-audit + Bandit |
| **Deploy Staging** (`deploy-staging.yml`) | Backend CI success on staging | Build → ACR push → Alembic migration → ACA deploy → health check → auto-rollback on failure |

### Deployment Architecture

**Staging** deploys to Azure Container Apps (ACA) via OIDC authentication (no static credentials):

1. Docker image built and pushed to Azure Container Registry
2. Trivy scans for HIGH/CRITICAL vulnerabilities
3. Alembic migration job runs as ACA container job
4. New ACA revision deployed with health check verification
5. Automatic rollback to previous image if health checks fail

**Docker images** are published to GitHub Container Registry (GHCR) on pushes to `main` and semantic version tags.

### Local CI Equivalents

```bash
# Backend
cd backend && make ci-pr       # PR gate
cd backend && make ci-main     # Staging gate

# iOS
cd ios/ClearSplit
bundle exec fastlane ios ci_pr    # PR gate
bundle exec fastlane ios ci_main  # Main gate
```

## Security

### Authentication and Token Security
- JWT access tokens with explicit type claims and 15-minute expiry
- Refresh tokens with unique JTI, server-side persistence, and rotation
- Revoked refresh token replay returns 401
- Bcrypt password hashing with timing-attack resistant login (dummy hash for unknown users)
- Case-insensitive identity normalization

### Transport and Data Protection
- Non-local environments require explicit HTTPS CORS origins (validated at startup)
- Database TLS enforced by default in non-local environments
- Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `HSTS` (non-local)
- Validation error responses are sanitized (raw input values stripped)

### Request Abuse Controls
- Process-local sliding window rate limiter on authentication and member preview endpoints
- Proxy header handling is opt-in with IP allowlist
- Receipt upload validation: content type, file size (10 MB), pixel count (25M), decompression bomb protection

### Secret Management
- All secrets loaded via environment variables using Pydantic `SecretStr`
- `.env` files gitignored; `.env.example` provided as template
- Pre-commit hook runs custom secret scanner on every commit
- CI runs TruffleHog (verified secrets), pip-audit (CVEs), and Bandit (code security)

### Incident Response
1. Rotate affected credentials immediately
2. Invalidate active refresh-token chains
3. Review commits, CI logs, and storage access
4. Run secret scan and patch before redeploy

For details, see [SECURITY.md](SECURITY.md).

## API Overview

All endpoints return JSON. Authenticated endpoints require a `Bearer` token in the `Authorization` header. OpenAPI docs (`/docs`, `/redoc`) are available only in `local` and `test` environments.

### Health
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/health/live` | No | Liveness probe |
| GET | `/health/ready` | No | Readiness probe (DB connectivity) |

### Auth
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/signup` | No | Register (rate limited: 5/5min) |
| POST | `/auth/login` | No | Authenticate (rate limited: 10/60s) |
| POST | `/auth/refresh` | No | Rotate refresh token |
| GET | `/auth/me` | Yes | Current user profile |

### Groups
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups` | Yes | Create group |
| GET | `/groups` | Yes | List user's groups |
| GET | `/groups/{id}` | Yes | Group details |
| DELETE | `/groups/{id}` | Yes | Delete group (owner only) |
| POST | `/groups/{id}/members/preview` | Yes | Preview member before adding |
| POST | `/groups/{id}/members` | Yes | Add member (owner only) |
| GET | `/groups/{id}/members` | Yes | List group members |

### Expenses
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups/{id}/expenses` | Yes | Create expense (idempotent) |
| GET | `/groups/{id}/expenses` | Yes | List group expenses |
| GET | `/expenses/{id}` | Yes | Get expense by ID |

### Balances and Settlements
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/groups/{id}/balances` | Yes | Live balances + transfer suggestions |
| POST | `/groups/{id}/settlements/compute` | Yes | Compute settlement batch (idempotent) |
| GET | `/groups/{id}/settlements/latest` | Yes | Latest settlement batch |
| POST | `/groups/{id}/settlement-payments` | Yes | Create payment |
| POST | `/settlement-payments/{id}/confirm` | Yes | Confirm pending payment |
| GET | `/groups/{id}/settlement-payments` | Yes | Payment history |

### Shopping Sessions
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/groups/{id}/shopping-sessions` | Yes | Create session |
| GET | `/groups/{id}/shopping-sessions` | Yes | List sessions |
| GET | `/shopping-sessions/{id}` | Yes | Session details with items |
| PATCH | `/shopping-sessions/{id}` | Yes | Update session (payer only) |
| POST | `/shopping-sessions/{id}/finalize` | Yes | Finalize session |
| DELETE | `/shopping-sessions/{id}` | Yes | Delete session (payer only) |
| PUT | `/shopping-sessions/{id}/participants` | Yes | Set participants |

### Shopping Items
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/shopping-sessions/{id}/items` | Yes | Create item |
| PATCH | `/items/{id}` | Yes | Update item |
| DELETE | `/items/{id}` | Yes | Delete item |
| PUT | `/items/{id}/sharers` | Yes | Set sharers (computes splits) |

### Receipts and OCR
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/shopping-sessions/{id}/receipt` | Yes | Upload receipt image |
| GET | `/receipts/{id}/download-url` | Yes | Get presigned download URL |
| DELETE | `/receipts/{id}` | Yes | Delete receipt |
| POST | `/receipts/{id}/extract-items` | Yes | Trigger OCR extraction |
| GET | `/receipts/{id}/extracted-items` | Yes | View extracted items |

### Friends
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/friends/requests` | Yes | Send friend request |
| POST | `/friends/requests/{id}/accept` | Yes | Accept request |
| POST | `/friends/requests/{id}/decline` | Yes | Decline request |
| GET | `/friends` | Yes | List friends |
| GET | `/friends/requests/incoming` | Yes | Incoming requests |
| GET | `/friends/requests/outgoing` | Yes | Outgoing requests |
| DELETE | `/friends/{id}` | Yes | Remove friendship |

## Documentation

Detailed documentation lives in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [Documentation Index](docs/INDEX.md) | Entry point for all docs |
| [Project Overview](docs/project-overview.md) | Product scope, features, and tech stack |
| [Architecture](docs/architecture.md) | System design, data flows, and key patterns |
| [Backend Reference](docs/backend-reference.md) | API endpoints, models, schemas, auth, config |
| [iOS Reference](docs/ios-reference.md) | App architecture, networking, views, navigation |
| [Repository Map](docs/repository-map.md) | Directory layout and file purposes |
| [Workflows & Operations](docs/workflows-and-operations.md) | Local dev, testing, CI/CD, deployment |
| [Dependencies](docs/dependencies.md) | Runtime and dev dependency versions |
| [Security Guide](SECURITY.md) | Security model, controls, incident response |
| [Non-Negotiables (ADR)](docs/adr/0001-non-negotiables.md) | Core architectural constraints |
| [Shopping Model](docs/features/SHOPPING_MODEL.md) | Shopping session feature spec |
| [Receipt OCR Decisions](docs/features/RECEIPT_OCR_DECISIONS.md) | OCR implementation decisions |
