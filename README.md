# ClearSplit

![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.122-009688?logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7-DC382D?logo=redis&logoColor=white)
![Celery](https://img.shields.io/badge/Celery-5.3-37814A?logo=celery&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-Container_Apps-0078D4?logo=microsoftazure&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-2088FF?logo=githubactions&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-metrics-E6522C?logo=prometheus&logoColor=white)

I built ClearSplit because splitting expenses with my college friend group was consistently painful. Bank apps let you request money, but they don't show what you're actually paying for — no receipt details, no item breakdown, no transparency. Someone does the math on their phone, everyone just trusts it, and mistakes happen. ClearSplit lets everyone in the group upload receipts, see every item, and know exactly what they owe and why.

## App Preview

<p align="center">
  <img src="docs/images/screenshots/01_login.png" width="180" alt="Login" />
  &nbsp;&nbsp;
  <img src="docs/images/screenshots/08_group_overview_full.png" width="180" alt="Group Overview" />
  &nbsp;&nbsp;
  <img src="docs/images/screenshots/07_shopping_sessions.png" width="180" alt="Shopping Sessions" />
  &nbsp;&nbsp;
  <img src="docs/images/screenshots/09_balances_settlement.png" width="180" alt="Balances & Settlement" />
</p>

<p align="center"><i>Login · Group Overview · Shopping Sessions · Settlement</i></p>

> Full 10-screen walkthrough with backend integration details: **[SHOWCASE.md](SHOWCASE.md)**

## CI/CD Pipeline

7 GitHub Actions workflows. Push to main triggers the full pipeline — production requires both CI and staging to pass on the same commit.

<p align="center">
  <img src="docs/diagrams/CI%3ACD%20Pipeline.png" width="920" alt="CI/CD Pipeline Diagram" />
</p>

## Architecture Overview

<p align="center">
  <img src="docs/diagrams/Architecture%20Overview.png" width="920" alt="Architecture Overview Diagram" />
</p>

## Tech Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Backend | FastAPI + Uvicorn | Async API with automatic OpenAPI documentation |
| Database | PostgreSQL + SQLAlchemy (async) | Strong transactional guarantees and concurrency support |
| Cache | Redis 7 | Cache-aside on balance queries — p50 −58%, throughput +91% |
| Task Queue | Celery + Redis broker | Offloads OCR from API workers; endpoint returns 202 in ~10ms |
| Auth | JWT + refresh rotation | Stateless auth with replay protection |
| Storage | AWS S3  | Direct client uploads/downloads without API proxying |
| OCR | Tesseract | Local OCR without external service dependency |
| Observability | Prometheus + Grafana | Request latency, cache hit/miss, job throughput metrics |
| Infra | Docker + Azure Container Apps | Managed container deployment with scaling support |
| CI/CD | GitHub Actions | Automated testing and deployment |
| iOS | SwiftUI  | Native UI with structured state management |


## Data Model

- **20 tables** across **6 domains**
  - Auth: users, refresh tokens, idempotency keys
  - Social: groups, memberships, friendships
  - Expenses: expenses, expense splits
  - Shopping: sessions, items, participants, splits
  - Receipts: uploads, extracted items, async jobs
  - Settlements: batches, settlements, payments, audit logs

Full table details: `docs/backend-reference.md` 
## Request Flow

<p align="center">
  <img src="docs/diagrams/Request%20flow.png" width="920" alt="Request Flow Diagram" />
</p>


## API Highlights

**49 endpoints** across **7 domain** routers.

Selected examples:

- **Expense Management**
  - Deterministic integer-cent splits
  - Live balance aggregation with transfer minimization — Redis-cached, invalidated on every mutation

- **Settlement**
  - Idempotent settlement computation
  - Immutable batch snapshots for audit consistency

- **Receipts & Async OCR**
  - Direct S3 uploads via presigned URLs
  - `POST /receipts/{id}/extract-items` returns 202 immediately; Celery worker runs Tesseract in the background
  - iOS polls `GET /jobs/{id}` until complete, then fetches extracted items

Full OpenAPI docs available at `/docs` in local development.

## Performance

Measured with `hey -n 200 -c 20` on local Docker Compose (PostgreSQL 16 + Redis 7).

### Balance queries — before vs after Redis cache

| Metric | Baseline (no cache) | With cache | Change |
|--------|--------------------|-----------:|-------:|
| p50 latency | 51.8 ms | 21.9 ms | **−58%** |
| p75 latency | 71.1 ms | 25.5 ms | **−64%** |
| p95 latency | 319.7 ms | 222.8 ms | **−30%** |
| Throughput | 246.6 req/s | 471.2 req/s | **+91%** |

### OCR endpoint — sync vs async

| | Before (sync) | After (async 202) |
|-|:---:|:---:|
| `POST /receipts/{id}/extract-items` | ~200–400 ms (blocked on Tesseract) | ~10 ms (enqueue + return) |

Full benchmark data: [`platform/benchmarks/RESULTS.md`](platform/benchmarks/RESULTS.md)

## Testing

153 tests across 14 files. CI enforces an 80% coverage gate on every PR and push to main.

| Area | Tests | Notes |
|------|------:|------|
| Shopping & receipts | 33 | Sessions, items, receipt flow, access control |
| Groups & expenses | 33 | CRUD, splits, balances |
| Settlements | 16 | Batch computation and confirmations |
| Auth | 17 | Login, token validation, refresh behavior |
| Async jobs & caching | 5 | 202→poll→200 flow, dedup, cache invalidation |

Testing practices:

- Each test runs in an isolated DB transaction (auto-rollback)
- External services are stubbed for deterministic tests
- CI enforces coverage and reproducibility
## Project Structure

```
backend/
├── app/
│   ├── api/        # Thin route handlers
│   ├── services/   # Business logic (splits, settlements, validation)
│   ├── models/     # SQLAlchemy ORM models
│   ├── schemas/    # Pydantic request/response schemas
│   ├── auth/       # JWT + authentication logic
│   ├── core/       # Middleware, rate limiting, idempotency, Redis cache
│   ├── worker/     # Celery app + OCR task
│   ├── db/         # Database configuration
│   └── main.py     # Application entry point
├── alembic/        # Database migrations
├── platform/
│   ├── benchmarks/ # hey load test results
│   └── observability/ # Prometheus + Grafana compose overlay
├── Dockerfile
└── docker-compose.yml
```

The backend follows a **thin routes, thick services** architecture.  
Route handlers remain minimal, while domain logic lives in the service layer.
## Getting Started

### Docker (Quickest)

```bash
git clone <repo-url> && cd ClearSplit
cp .env.example .env
echo "JWT_SECRET=$(openssl rand -hex 32)" >> .env
docker compose up --build
# API  → http://localhost:8000
# Docs → http://localhost:8000/docs
```

`docker-compose.yml` runs PostgreSQL 16, Redis 7, the API, and a Celery worker. The worker and API share the same image; only the entrypoint differs.

### Local Dev (No Docker)

```bash
cd backend
python3.11 -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt
# Requires PostgreSQL 16 running + DATABASE_URL in .env
alembic upgrade head
make run   # uvicorn --reload on :8000
```

### Makefile Targets

| Target | What It Does |
|--------|-------------|
| `make run` | Start dev server with auto-reload |
| `make test` | Run full test suite |
| `make test-pr` | PR gate — non-e2e, 80% coverage minimum |
| `make test-all` | Main gate — full suite, 80% coverage minimum |
| `make lint-ci` | Ruff linting |
| `make ci-pr` | Lint + PR tests (matches CI) |
| `make ci-main` | Lint + all tests (matches CI) |
| `make migrate` | `alembic upgrade head` |

## iOS Client

Native SwiftUI app with zero external dependencies. MVVM architecture, Keychain-backed auth with silent token refresh, and protocol-based services for testability. The networking layer — including multipart uploads, automatic 401 retry, and concurrent refresh deduplication — is built on Foundation alone.

See the full 10-screen walkthrough: **[SHOWCASE.md](SHOWCASE.md)**

## Documentation

| Document | Description |
|----------|-------------|
| [SHOWCASE.md](SHOWCASE.md) | iOS app walkthrough — 9 screens with backend integration details |
| [docs/architecture.md](docs/architecture.md) | System topology, layer architecture, domain flows |
| [docs/backend-reference.md](docs/backend-reference.md) | Full API surface, env vars, data model, auth rules |
| [docs/workflows-and-operations.md](docs/workflows-and-operations.md) | CI/CD pipelines, deployment flows, troubleshooting |
| [docs/ios-reference.md](docs/ios-reference.md) | iOS architecture, networking layer, state management |
| [docs/repository-map.md](docs/repository-map.md) | File-level codebase map |
| [SECURITY.md](SECURITY.md) | Security policy |
