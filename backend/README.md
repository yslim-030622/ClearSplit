# Backend (FastAPI)

Conventions:
- FastAPI with async stack, OpenAPI-first; Pydantic schemas in `app/schemas`.
- SQLAlchemy 2.0 models in `app/models`; Alembic migrations in `alembic/`.
- Postgres via asyncpg; one DB transaction per request when mutating.
- Idempotency middleware required on all writes; optimistic locking (`version`) where specified.
- Settlements are immutable snapshots; status updates only.

Layout:
- `app/api/` — route modules by feature (auth, groups, expenses, settlements).
- `app/core/` — settings, logging, dependencies, security utilities.
- `app/db/` — session management, base metadata, migration hooks.
- `app/models/` — SQLAlchemy models.
- `app/schemas/` — request/response DTOs.
- `app/services/` — business logic.
- `app/auth/` — JWT helpers, password hashing, auth dependencies.
- `app/settlement/` — settlement engine.
- `app/tests/` — unit and integration tests (requires Postgres).
