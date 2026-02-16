# Repository Map

## Top Level

- `backend/`: FastAPI service, domain logic, migrations, tests
- `ios/`: SwiftUI client and iOS build/test automation scripts
- `docs/`: project documentation
- `scripts/`: repo-level helper scripts (security checks, S3 smoke test)
- `docker-compose.yml`: local database + API orchestration

## Backend Structure

- `backend/app/main.py`: FastAPI app wiring, middleware, health endpoints
- `backend/app/api/`: HTTP route handlers by feature domain
- `backend/app/services/`: business logic and authorization rules
- `backend/app/models/`: SQLAlchemy models
- `backend/app/schemas/`: Pydantic request/response schemas
- `backend/app/auth/`: JWT, password hashing, auth dependency, refresh token rotation
- `backend/app/core/`: app settings, idempotency, rate limiting, identity normalization
- `backend/app/db/`: SQLAlchemy engine/session setup and TLS connect-arg handling
- `backend/alembic/`: migration environment and migration history
- `backend/app/tests/`: backend tests (auth, groups, expenses, settlements, shopping, OCR)

## iOS Structure

- `ios/ClearSplit/Sources/ClearSplit/State/AppState.swift`: app-level orchestration and shared state
- `ios/ClearSplit/Sources/ClearSplit/Networking/`: API client + domain services
- `ios/ClearSplit/Sources/ClearSplit/Models/`: Codable DTOs and UI-facing data models
- `ios/ClearSplit/Sources/ClearSplit/ViewModels/`: screen/view-specific state and actions
- `ios/ClearSplit/Sources/ClearSplit/Views/`: SwiftUI screens and reusable components
- `ios/ClearSplit/Sources/ClearSplit/DesignSystem/`: colors, tokens, and button styles
- `ios/ClearSplit/scripts/`: deterministic build/test/lint/archive scripts

## Operational Scripts

- `backend/Makefile`: backend install, run, lint, test, migration shortcuts
- `scripts/secret-scan.sh`: tracked-file secret scanning
- `scripts/verify-security.sh`: repo security baseline checks
- `scripts/s3_smoke_test.py`: quick object storage upload/download URL validation
