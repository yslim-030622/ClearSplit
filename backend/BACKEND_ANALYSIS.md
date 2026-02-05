# ClearSplit Backend - Comprehensive Analysis Report

## Executive Summary

**ClearSplit** is a **Splitwise-style expense splitting application** with a focus on **grocery receipt splitting**. The backend is a **FastAPI-based REST API** that serves as the source of truth for an iOS client application. It handles group expense management, shopping sessions with item-level splits, and automatic settlement calculations.

---

## 1. Project Overview

### Purpose

ClearSplit helps groups (especially roommates) track shared expenses and automatically calculate who owes whom. The current focus is on **Shopping Sessions** - a feature for splitting grocery receipts with item-level granularity.

### Core Value Proposition

- Create groups and invite members
- Track expenses with automatic equal splits
- Handle shopping trips with receipt uploads and item-level splitting
- Automatically compute settlement suggestions (who should pay whom)
- Immutable settlement snapshots for auditability

---

## 2. Technology Stack

### Framework & Runtime

- **FastAPI 0.111.0** - Modern async Python web framework
- **Python 3.11+** - Programming language
- **Uvicorn** - ASGI server for running FastAPI

### Database

- **PostgreSQL 16** - Primary database
- **SQLAlchemy 2.0.30** - ORM with async support
- **asyncpg 0.29.0** - Async PostgreSQL driver
- **Alembic 1.13.1** - Database migration tool

### Authentication & Security

- **python-jose** - JWT token handling
- **bcrypt 4.1.2** - Password hashing
- **HTTPBearer** - Token-based authentication

### Data Validation

- **Pydantic 2.8.2** - Request/response validation and serialization
- **pydantic-settings 2.3.3** - Configuration management

### Testing

- **pytest 8.3.2** - Testing framework
- **pytest-asyncio 0.25.2** - Async test support
- **httpx 0.27.0** - HTTP client for testing

### Development Tools

- **python-dotenv 1.0.1** - Environment variable management
- **Docker & Docker Compose** - Containerization and local development

---

## 3. Architecture Overview

### High-Level Architecture

```
┌─────────────┐
│   iOS App   │
└──────┬──────┘
       │ HTTP/REST
       │ JWT Bearer Tokens
       ▼
┌─────────────────────────────────────┐
│         FastAPI Backend             │
│  ┌───────────────────────────────┐  │
│  │   API Routes (app/api/)       │  │
│  │   - auth.py                   │  │
│  │   - groups.py                 │  │
│  │   - expenses.py               │  │
│  │   - shopping.py               │  │
│  │   - settlements.py            │  │
│  └───────────┬───────────────────┘  │
│              │                       │
│  ┌───────────▼───────────────────┐  │
│  │  Services (app/services/)     │  │
│  │  Business Logic Layer         │  │
│  └───────────┬───────────────────┘  │
│              │                       │
│  ┌───────────▼───────────────────┐  │
│  │  Models (app/models/)          │  │
│  │  SQLAlchemy ORM Models         │  │
│  └───────────┬───────────────────┘  │
└──────────────┼───────────────────────┘
               │
               ▼
        ┌──────────────┐
        │  PostgreSQL  │
        │   Database   │
        └──────────────┘
```

### Design Patterns

1. **Layered Architecture**
   - **API Layer** (`app/api/`) - HTTP endpoints, request/response handling
   - **Service Layer** (`app/services/`) - Business logic, validation
   - **Model Layer** (`app/models/`) - Database entities
   - **Schema Layer** (`app/schemas/`) - Pydantic models for validation

2. **Dependency Injection**
   - FastAPI's dependency system for database sessions
   - Authentication dependencies for protected routes

3. **Repository Pattern** (implicit)
   - Services encapsulate database access
   - Models define data structure

---

## 4. Directory Structure

```
backend/
├── app/
│   ├── api/              # API route handlers
│   │   ├── auth.py       # Authentication endpoints
│   │   ├── groups.py     # Group management
│   │   ├── expenses.py   # Expense tracking
│   │   ├── shopping.py   # Shopping sessions
│   │   └── settlements.py # Settlement calculations
│   │
│   ├── auth/             # Authentication utilities
│   │   ├── dependencies.py # Auth dependencies
│   │   ├── jwt.py        # JWT token creation/validation
│   │   └── password.py   # Password hashing
│   │
│   ├── core/             # Core configuration
│   │   ├── config.py     # Settings management
│   │   └── idempotency.py # Idempotency key handling
│   │
│   ├── db/               # Database setup
│   │   ├── __init__.py   # Base model class
│   │   └── session.py   # Database session factory
│   │
│   ├── models/           # SQLAlchemy models (15 models)
│   │   ├── user.py
│   │   ├── group.py
│   │   ├── membership.py
│   │   ├── expense.py
│   │   ├── expense_split.py
│   │   ├── shopping_session.py
│   │   ├── shopping_item.py
│   │   ├── shopping_item_split.py
│   │   ├── settlement.py
│   │   └── ... (others)
│   │
│   ├── schemas/          # Pydantic schemas
│   │   ├── auth.py
│   │   ├── user.py
│   │   ├── group.py
│   │   ├── expense.py
│   │   ├── shopping.py
│   │   └── settlement.py
│   │
│   ├── services/         # Business logic
│   │   ├── group.py
│   │   ├── membership.py
│   │   ├── expense.py
│   │   ├── shopping.py
│   │   └── settlement.py
│   │
│   ├── tests/            # Test suite
│   │   ├── conftest.py
│   │   ├── test_auth.py
│   │   ├── test_expenses.py
│   │   └── ... (others)
│   │
│   └── main.py           # FastAPI app entry point
│
├── alembic/              # Database migrations
│   ├── env.py
│   └── versions/         # Migration files
│
├── requirements.txt      # Python dependencies
├── alembic.ini          # Alembic configuration
├── Dockerfile           # Container definition
├── Makefile             # Development commands
└── README.md            # Backend documentation
```

---

## 5. Database Schema

### Core Entities

#### Users (`users`)

- `id` (UUID, PK)
- `username` (CITEXT, unique)
- `email` (CITEXT, unique)
- `password_hash` (Text)
- `first_name`, `last_name` (Text)
- `created_at`, `updated_at` (Timestamp)

#### Groups (`groups`)

- `id` (UUID, PK)
- `name` (Text)
- `currency` (String(3), default: "USD")
- `version` (Integer) - Optimistic locking
- `created_at`, `updated_at` (Timestamp)

#### Memberships (`memberships`)

- `id` (UUID, PK)
- `group_id` (UUID, FK → groups)
- `user_id` (UUID, FK → users)
- `role` (Enum: owner, member, viewer)
- `created_at` (Timestamp)
- **Unique constraint**: (group_id, user_id)

#### Expenses (`expenses`)

- `id` (UUID, PK)
- `group_id` (UUID, FK → groups)
- `title` (Text)
- `amount_cents` (BigInteger) - **Money stored as cents**
- `currency` (String(3))
- `paid_by` (UUID) - Membership ID
- `expense_date` (Date)
- `memo` (Text, nullable)
- `version` (Integer) - Optimistic locking
- `created_at`, `updated_at` (Timestamp)

#### Expense Splits (`expense_splits`)

- `id` (UUID, PK)
- `expense_id` (UUID, FK → expenses)
- `membership_id` (UUID, FK → memberships)
- `amount_cents` (BigInteger)
- `created_at` (Timestamp)

### Shopping Feature

#### Shopping Sessions (`shopping_sessions`)

- `id` (UUID, PK)
- `group_id` (UUID, FK → groups)
- `title` (Text)
- `shopping_date` (Date, nullable)
- `total_amount` (Numeric(10,2), nullable) - Optional quick total
- `currency` (String(3))
- `paid_by_membership_id` (UUID, FK → memberships)
- `created_at` (Timestamp)

#### Shopping Items (`shopping_items`)

- `id` (UUID, PK)
- `session_id` (UUID, FK → shopping_sessions)
- `name` (Text)
- `quantity` (Integer)
- `total_cents` (BigInteger)
- `unit_price_cents` (BigInteger)
- `created_at` (Timestamp)

#### Shopping Item Splits (`shopping_item_splits`)

- `id` (UUID, PK)
- `item_id` (UUID, FK → shopping_items)
- `membership_id` (UUID, FK → memberships)
- `amount_cents` (BigInteger) - Computed equal split
- `created_at` (Timestamp)

#### Shopping Session Participants (`shopping_session_participants`)

- `id` (UUID, PK)
- `session_id` (UUID, FK → shopping_sessions)
- `membership_id` (UUID, FK → memberships)
- `created_at` (Timestamp)

#### Receipt Uploads (`receipt_uploads`)

- `id` (UUID, PK)
- `session_id` (UUID, FK → shopping_sessions)
- `file_path` (Text) - Storage path
- `file_name` (Text)
- `file_size_bytes` (BigInteger)
- `mime_type` (Text)
- `uploaded_by_membership_id` (UUID, FK → memberships)
- `created_at` (Timestamp)

### Settlement Feature

#### Settlement Batches (`settlement_batches`)

- `id` (UUID, PK)
- `group_id` (UUID, FK → groups)
- `status` (Enum: suggested, paid, voided)
- `total_settlements` (Integer)
- `version` (Integer) - Optimistic locking
- `created_at`, `updated_at` (Timestamp)
- `voided_reason` (Text, nullable)

#### Settlements (`settlements`)

- `id` (UUID, PK)
- `batch_id` (UUID, FK → settlement_batches)
- `group_id` (UUID, FK → groups)
- `from_membership` (UUID, FK → memberships)
- `to_membership` (UUID, FK → memberships)
- `amount_cents` (BigInteger)
- `status` (Enum: suggested, paid, voided)
- `created_at` (Timestamp)
- **Constraints**:
  - `amount_cents > 0`
  - `from_membership <> to_membership`

### Supporting Tables

#### Idempotency Keys (`idempotency_keys`)

- Stores request hashes and responses for idempotent operations
- Prevents duplicate operations on retries

#### Activity Logs (`activity_logs`)

- Audit trail for group activities

---

## 6. API Endpoints

### Authentication (`/auth`)

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/auth/signup` | Create new user account | No |
| POST | `/auth/login` | Authenticate and get tokens | No |
| POST | `/auth/refresh` | Refresh access token | No |
| GET | `/auth/me` | Get current user info | Yes |

**Token Types:**

- **Access Token**: Short-lived (15 minutes default)
- **Refresh Token**: Long-lived (30 days default)

### Groups (`/groups`)

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/groups` | Create a new group | Yes |
| GET | `/groups` | List user's groups | Yes |
| GET | `/groups/{group_id}` | Get group details | Yes (member) |
| POST | `/groups/{group_id}/members/preview` | Preview member invite | Yes (owner) |
| POST | `/groups/{group_id}/members` | Add member to group | Yes (owner) |
| GET | `/groups/{group_id}/members` | List group members | Yes (member) |

### Expenses (`/groups/{group_id}/expenses`)

| Method | Endpoint | Description | Auth Required | Idempotent |
|--------|----------|-------------|---------------|------------|
| POST | `/groups/{group_id}/expenses` | Create expense with equal splits | Yes (member) | Yes |
| GET | `/groups/{group_id}/expenses` | List group expenses | Yes (member) | No |
| GET | `/expenses/{expense_id}` | Get expense by ID | Yes (member) | No |

**Features:**

- Automatic equal split calculation
- Auto-computes settlements after creation
- Supports idempotency via `Idempotency-Key` header

### Shopping Sessions (`/shopping-sessions`)

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| POST | `/groups/{group_id}/shopping-sessions` | Create shopping session | Yes (member) |
| GET | `/groups/{group_id}/shopping-sessions` | List sessions | Yes (member) |
| GET | `/shopping-sessions/{session_id}` | Get session details | Yes (member) |
| PUT | `/shopping-sessions/{session_id}/participants` | Set participants | Yes (payer) |
| POST | `/shopping-sessions/{session_id}/receipt` | Upload receipt | Yes (payer) |
| POST | `/shopping-sessions/{session_id}/items` | Create item | Yes (payer) |
| PUT | `/items/{item_id}/sharers` | Set item sharers | Yes (payer) |

**Authorization Rules:**

- Only the **payer** (paid_by_membership_id) can:
  - Set participants
  - Upload receipts
  - Create items
  - Set item sharers

### Settlements (`/settlements`)

| Method | Endpoint | Description | Auth Required | Idempotent |
|--------|----------|-------------|---------------|------------|
| POST | `/groups/{group_id}/settlements/compute` | Compute new settlement batch | Yes (member) | Yes |
| GET | `/groups/{group_id}/settlements/latest` | Get latest batch | Yes (member) | No |
| PATCH | `/settlements/{settlement_id}` | Mark settlement as paid | Yes (debtor) | No |

**Settlement Algorithm:**

- Computes minimal transfers to settle all debts
- Creates immutable snapshot (batch)
- Only status updates allowed (paid/voided)

### Health Check

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check endpoint |

---

## 7. Authentication & Security

### Authentication Flow

1. **Signup/Login**
   - User provides credentials (username/email + password)
   - Server validates and returns:
     - Access token (JWT, 15 min expiry)
     - Refresh token (JWT, 30 days expiry)
     - User information

2. **Protected Routes**
   - Client sends: `Authorization: Bearer <access_token>`
   - Server validates token and extracts user ID
   - User is injected into route handler via dependency

3. **Token Refresh**
   - Client sends refresh token
   - Server validates and issues new access token
   - Refresh token remains valid

### Security Features

1. **Password Security**
   - Passwords hashed with bcrypt
   - Never stored in plaintext
   - Never returned in API responses

2. **JWT Tokens**
   - Signed with HS256 algorithm
   - Contains: user_id, email, token type, expiration
   - Separate access/refresh tokens

3. **Authorization**
   - Role-based access control (owner, member, viewer)
   - Group membership required for most operations
   - Payer-only operations for shopping sessions

4. **Idempotency**
   - Prevents duplicate operations
   - Uses request hash + endpoint + user_id
   - Returns cached response on duplicate requests

5. **Input Validation**
   - Pydantic schemas validate all inputs
   - Type checking and constraint validation
   - Detailed error messages

---

## 8. Key Features & Business Logic

### 1. Group Management

- Users create groups with name and currency
- Creator automatically becomes owner
- Owners can invite members by email/username
- Three roles: owner, member, viewer

### 2. Expense Tracking

- Create expenses with title, amount, date
- Specify who paid (membership ID)
- Specify who to split among (list of membership IDs)
- **Automatic equal split calculation**
- Splits stored in `expense_splits` table
- **Auto-computes settlements** after expense creation

### 3. Shopping Sessions (Primary Feature)

- Create shopping trips with title, date, payer
- Add participants (who was shopping)
- Upload receipt images (optional)
- Add line items manually:
  - Name, quantity, total price, unit price
- Assign sharers to each item
- **Automatic equal split calculation** per item
- **Deterministic remainder distribution** (no rounding errors)

**Workflow:**

1. Create session → Set participants → Upload receipt (optional)
2. Add items → Set sharers for each item
3. System computes splits automatically

### 4. Settlement Engine

- Computes who owes whom based on expenses/shopping
- Creates **immutable settlement batches**
- Uses minimal transfer algorithm
- Status tracking: suggested → paid → voided
- Only status updates allowed (no edits to amounts)

### 5. Idempotency

- All write operations support idempotency
- Client sends `Idempotency-Key` header
- Server stores request hash + response
- Duplicate requests return cached response

---

## 9. Code Organization Patterns

### API Routes (`app/api/`)

- **Thin controllers** - Minimal logic, delegate to services
- **Dependency injection** - Auth, database session
- **Request/response models** - Pydantic schemas
- **Error handling** - HTTP exceptions with proper status codes

### Services (`app/services/`)

- **Business logic** - All complex operations
- **Database access** - Encapsulated in services
- **Validation** - Business rules enforcement
- **Reusable functions** - Shared across routes

### Models (`app/models/`)

- **SQLAlchemy 2.0** - Modern ORM syntax
- **Type hints** - Full type annotations
- **Relationships** - Properly defined with back_populates
- **Constraints** - Database-level validation

### Schemas (`app/schemas/`)

- **Pydantic models** - Request/response validation
- **Separation** - Create, Read, Update schemas
- **Serialization** - Automatic JSON conversion

---

## 10. Database Migrations

### Migration History

1. **20241218_0001_initial.py**
   - Core tables: users, groups, memberships, expenses, expense_splits
   - Settlement tables: settlement_batches, settlements
   - Activity logs, idempotency keys

2. **20250107_0002_add_shopping_tables.py**
   - Shopping sessions, items, item splits
   - Shopping session participants
   - Receipt uploads

3. **20250110_0003_add_total_amount_to_sessions.py**
   - Added `total_amount` to shopping_sessions

4. **20260127_0004_add_first_last_name_to_users.py**
   - Added first_name, last_name to users

5. **20260128_0005_add_username_to_users.py**
   - Added username field to users

### Migration Workflow

```bash
# Create new migration
alembic revision --autogenerate -m "description"

# Apply migrations
alembic upgrade head

# Rollback
alembic downgrade -1
```

---

## 11. Configuration & Environment

### Environment Variables

Required in `.env` file:

```bash
# Database
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/clearsplit

# JWT
JWT_SECRET=your-secret-key-here
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30

# Environment
ENV=local
```

### Settings Management

- Uses `pydantic-settings` for configuration
- Loads from `.env` file
- Type-safe settings class
- Cached with `@lru_cache`

---

## 12. Development Workflow

### Local Development

1. **Start Database**

   ```bash
   docker-compose up -d db
   ```

2. **Install Dependencies**

   ```bash
   cd backend
   make install
   ```

3. **Run Migrations**

   ```bash
   alembic upgrade head
   ```

4. **Start Server**

   ```bash
   make run
   # Server runs on http://localhost:8000
   ```

5. **Run Tests**

   ```bash
   make test
   ```

### Docker Development

```bash
# Start all services
docker-compose up

# API available at http://localhost:8000
# Database at localhost:5432
```

### API Documentation

- **Swagger UI**: `http://localhost:8000/docs`
- **ReDoc**: `http://localhost:8000/redoc`
- **OpenAPI JSON**: `http://localhost:8000/openapi.json`

---

## 13. Testing

### Test Structure

- Tests in `app/tests/`
- Uses pytest with async support
- `conftest.py` for fixtures (database, test client)
- Separate test files per feature

### Test Coverage

- Authentication tests
- Expense tests
- Group tests
- Settlement tests
- Shopping tests
- Model tests
- Health check tests

### Running Tests

```bash
# All tests
make test

# Specific test file
pytest app/tests/test_auth.py

# With coverage
pytest --cov=app
```

---

## 14. Notable Design Decisions

### 1. Money as Integer Cents

- **Why**: Avoids floating-point precision errors
- **Storage**: `BigInteger` for `amount_cents`
- **API**: Accepts/returns cents, not dollars

### 2. Immutable Settlements

- **Why**: Audit trail, prevents accidental changes
- **Implementation**: New batch created for each computation
- **Updates**: Only status changes allowed

### 3. Optimistic Locking

- **Why**: Prevents concurrent modification conflicts
- **Implementation**: `version` field on groups, expenses, settlement_batches
- **Usage**: Increment on updates, check on conflicts

### 4. Composite Foreign Keys

- **Why**: Ensures data integrity across group boundaries
- **Implementation**: Deferred constraints on settlements
- **Benefit**: Prevents orphaned records

### 5. Membership-Based Authorization

- **Why**: Users can have different roles in different groups
- **Implementation**: All operations use membership IDs, not user IDs
- **Benefit**: Flexible permission model

### 6. Async/Await Throughout

- **Why**: Better performance for I/O-bound operations
- **Implementation**: AsyncSession, async route handlers
- **Benefit**: Handles concurrent requests efficiently

---

## 15. Current State & Health

### ✅ Strengths

- **Modern stack** - FastAPI, SQLAlchemy 2.0, async/await
- **Well-organized** - Clear separation of concerns
- **Type-safe** - Full type hints, Pydantic validation
- **Secure** - JWT auth, password hashing, input validation
- **Idempotent** - Prevents duplicate operations
- **Tested** - Test suite in place
- **Documented** - Good code organization, README

### ⚠️ Areas for Improvement

- **Error handling** - Could be more comprehensive
- **Logging** - Basic logging, could be enhanced
- **Rate limiting** - Not implemented (mentioned in preview endpoint)
- **File storage** - Receipt uploads need storage solution
- **Caching** - No caching layer for frequently accessed data
- **Monitoring** - No observability/metrics infrastructure

### 🔄 Active Development

- Shopping sessions feature is the current focus
- Receipt upload functionality exists but needs storage backend
- Settlement engine is functional but may need optimization

---

## 16. Integration Points

### iOS Client

- REST API communication
- JWT token storage in Keychain
- Token refresh handling
- Error handling and retry logic

### Database

- PostgreSQL 16
- Async connection pooling
- Transaction management per request

### Future Integrations (Potential)

- File storage service (S3, etc.) for receipts
- Email service for invitations
- Push notifications
- Analytics/monitoring

---

## 17. API Response Examples

### Signup Response

```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "username": "johndoe",
    "email": "john@example.com",
    "first_name": "John",
    "last_name": "Doe"
  }
}
```

### Expense Response

```json
{
  "id": "uuid",
  "group_id": "uuid",
  "title": "Dinner",
  "amount_cents": 5000,
  "currency": "USD",
  "paid_by": "membership-uuid",
  "expense_date": "2024-01-15",
  "memo": "Restaurant",
  "splits": [
    {
      "id": "uuid",
      "membership_id": "uuid",
      "amount_cents": 2500
    }
  ]
}
```

### Settlement Batch Response

```json
{
  "id": "uuid",
  "group_id": "uuid",
  "status": "suggested",
  "total_settlements": 2,
  "settlements": [
    {
      "id": "uuid",
      "from_membership": "uuid",
      "to_membership": "uuid",
      "amount_cents": 1500,
      "status": "suggested"
    }
  ]
}
```

---

## 18. Summary

ClearSplit backend is a **well-architected, modern Python API** built with FastAPI. It provides:

- ✅ **Robust authentication** with JWT tokens
- ✅ **Group expense management** with automatic splits
- ✅ **Shopping session feature** for grocery receipt splitting
- ✅ **Automatic settlement calculations**
- ✅ **Idempotent operations** for reliability
- ✅ **Type-safe codebase** with full type hints
- ✅ **Comprehensive test suite**

The codebase follows best practices with clear separation of concerns, proper error handling, and a focus on data integrity. The shopping sessions feature is the current primary focus, with receipt uploads and item-level splitting capabilities.

**Next Steps for Development:**

1. Implement file storage for receipt uploads
2. Add rate limiting to prevent abuse
3. Enhance logging and monitoring
4. Optimize settlement algorithm for large groups
5. Add email notifications for invitations
6. Implement push notifications for iOS

---

*Report generated: January 2025*
*Backend Version: Based on FastAPI 0.111.0, SQLAlchemy 2.0.30*
