# ClearSplit Backend

FastAPI backend for ClearSplit expense splitting application.

## Features

- **Authentication**: JWT-based auth with access and refresh tokens
- **Groups**: Create and manage expense groups
- **Memberships**: Add members to groups with role-based access
- **Expenses**: Create expenses with equal splits (MVP)
- **Idempotency**: Support for idempotent expense creation

## Quick Start

### Prerequisites

- Docker Desktop
- Python 3.12+
- PostgreSQL 16 (via Docker)

### Setup

1. **Start database:**
   ```bash
   docker-compose up -d db
   ```

2. **Install dependencies:**
   ```bash
   cd backend
   make install
   # or
   pip install -r requirements.txt
   ```

3. **Run migrations:**
   ```bash
   alembic upgrade head
   ```

4. **Start server:**
   ```bash
   make run
   ```

5. **Test API:**
   ```bash
   ./test_api.sh
   ```

## API Documentation

- **Interactive Docs**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **Testing Guide**: See `API_TESTING.md`

## Project Structure

```
backend/
├── app/
│   ├── api/          # FastAPI route handlers
│   ├── auth/          # Authentication utilities
│   ├── core/          # Core configuration and utilities
│   ├── db/            # Database session management
│   ├── models/        # SQLAlchemy ORM models
│   ├── schemas/       # Pydantic request/response schemas
│   ├── services/      # Business logic layer
│   └── tests/         # Test suite
├── alembic/           # Database migrations
└── requirements.txt   # Python dependencies
```

## Testing

Run all tests:
```bash
pytest app/tests/ -v
```

Run specific test suite:
```bash
pytest app/tests/test_auth.py -v
pytest app/tests/test_groups.py -v
pytest app/tests/test_expenses.py -v
```

## Development

### Code Style

- Follow PEP 8
- Use type hints
- Document functions with docstrings
- Keep business logic in services layer

### Database Migrations

Create a new migration:
```bash
alembic revision --autogenerate -m "description"
```

Apply migrations:
```bash
alembic upgrade head
```

Rollback:
```bash
alembic downgrade -1
```

## Environment Variables

Required in `.env`:
- `DATABASE_URL`: PostgreSQL connection string
- `JWT_SECRET`: Secret key for JWT signing
- `ENV`: Environment (local, staging, production)

## Documentation

- `API_TESTING.md`: Complete API testing guide
- `AUTH_IMPLEMENTATION.md`: Authentication implementation details
- `GROUPS_IMPLEMENTATION.md`: Groups and memberships
- `EXPENSES_IMPLEMENTATION.md`: Expenses and splits
