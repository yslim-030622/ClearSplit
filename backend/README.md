# ClearSplit Backend

FastAPI-based backend for the ClearSplit expense splitting application.

## Features

- **Phase 1: Authentication** ✅
  - User registration and login
  - JWT-based authentication
  - Token refresh mechanism
  
- **Phase 2: Groups & Memberships** ✅
  - Create and manage expense groups
  - Invite and manage group members
  - Role-based access control (Owner/Member)
  
- **Phase 3: Expenses** ✅
  - Create expenses with equal split
  - Automatic split calculation with remainder handling
  - Idempotency support
  
- **Phase 4: Settlements** ✅
  - Compute optimal settlement transfers
  - Minimize number of transactions
  - Track payment status

## Tech Stack

- **Framework**: FastAPI
- **Database**: PostgreSQL with asyncpg
- **ORM**: SQLAlchemy 2.0 (async)
- **Authentication**: JWT with bcrypt password hashing
- **Migrations**: Alembic
- **Testing**: pytest with pytest-asyncio

## Quick Start

### Prerequisites

- Python 3.12+
- PostgreSQL 14+
- Docker (optional, for running PostgreSQL)

### Setup

1. **Start PostgreSQL**:
   ```bash
   docker-compose up -d
   ```

2. **Set up environment**:
   ```bash
   cd backend
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

3. **Configure environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

4. **Run migrations**:
   ```bash
   alembic upgrade head
   ```

5. **Start the server**:
   ```bash
   uvicorn app.main:app --reload
   ```

   The API will be available at `http://localhost:8000`
   API documentation: `http://localhost:8000/docs`

## API Testing

### Automated Testing Script

```bash
./test_api.sh
```

### Manual Testing

See [API_TESTING.md](./API_TESTING.md) for detailed step-by-step instructions.

### Quick Smoke Test

```bash
./QUICK_TEST.sh
```

## Running Tests

### All Tests
```bash
pytest -v
```

### By Category
```bash
# Authentication tests
pytest app/tests/test_auth.py -v

# Group tests
pytest app/tests/test_groups.py -v

# Expense tests
pytest app/tests/test_expenses.py -v

# Settlement tests
pytest app/tests/test_settlements.py -v

# Model tests
pytest app/tests/test_models.py -v
```

### Single Test
```bash
pytest app/tests/test_auth.py::test_signup_success -v
```

**Note**: Some tests may fail when run in large batches due to async connection pooling issues. All tests pass when run individually. See [TESTING_STATUS.md](./TESTING_STATUS.md) for details.

## Project Structure

```
backend/
├── app/
│   ├── api/           # API route handlers
│   │   ├── auth.py
│   │   ├── expenses.py
│   │   ├── groups.py
│   │   └── settlements.py
│   ├── auth/          # Authentication utilities
│   ├── core/          # Core configuration
│   ├── db/            # Database session management
│   ├── models/        # SQLAlchemy models
│   ├── schemas/       # Pydantic schemas
│   ├── services/      # Business logic
│   └── tests/         # Test suite
├── alembic/           # Database migrations
├── .env               # Environment configuration
└── requirements.txt   # Python dependencies
```

## API Endpoints

### Authentication
- `POST /auth/signup` - Register new user
- `POST /auth/login` - User login
- `POST /auth/refresh` - Refresh access token
- `GET /auth/me` - Get current user info

### Groups
- `POST /groups` - Create group
- `GET /groups` - List user's groups
- `GET /groups/{group_id}` - Get group details
- `POST /groups/{group_id}/members` - Add member to group
- `GET /groups/{group_id}/members` - List group members

### Expenses
- `POST /groups/{group_id}/expenses` - Create expense
- `GET /groups/{group_id}/expenses` - List group expenses
- `GET /expenses/{expense_id}` - Get expense details

### Settlements
- `POST /groups/{group_id}/settlements` - Compute settlement batch
- `GET /groups/{group_id}/settlements` - List settlement batches
- `GET /settlements/{batch_id}` - Get settlement details
- `POST /settlements/{settlement_id}/mark-paid` - Mark as paid

## Development

### Database Migrations

Create a new migration:
```bash
alembic revision --autogenerate -m "Description"
```

Apply migrations:
```bash
alembic upgrade head
```

Rollback migration:
```bash
alembic downgrade -1
```

### Code Style

The project follows Python best practices:
- Type hints for function signatures
- Pydantic for data validation
- Async/await for all I/O operations
- Comprehensive error handling

## Documentation

- [API Testing Guide](./API_TESTING.md) - Manual API testing instructions
- [Testing Status](./TESTING_STATUS.md) - Current test suite status
- [Authentication Implementation](./AUTH_IMPLEMENTATION.md) - Auth system details
- [Groups Implementation](./GROUPS_IMPLEMENTATION.md) - Groups & memberships
- [Expenses Implementation](./EXPENSES_IMPLEMENTATION.md) - Expense management

## Environment Variables

```env
# Environment
ENV=local

# Database
DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit

# JWT Configuration
JWT_SECRET=your-secret-key-here
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
```

## Troubleshooting

### Database Connection Issues

If you see `role "clearsplit" does not exist`:
```bash
# Connect to PostgreSQL and create user/database
docker-compose exec postgres psql -U postgres
CREATE USER clearsplit WITH PASSWORD 'clearsplit';
CREATE DATABASE clearsplit OWNER clearsplit;
```

### Migration Issues

Reset database and reapply migrations:
```bash
alembic downgrade base
alembic upgrade head
```

### Test Failures

Run tests individually if batch execution fails:
```bash
pytest app/tests/test_auth.py::test_signup_success -v
```

## License

MIT
