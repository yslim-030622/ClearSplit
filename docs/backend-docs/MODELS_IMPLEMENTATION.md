# SQLAlchemy Models Implementation Summary

## Files Created/Modified

### Created Files:
1. `app/db/__init__.py` - Base declarative class for all models
2. `app/models/user.py` - User model
3. `app/models/group.py` - Group model
4. `app/models/membership.py` - Membership model with enum role
5. `app/models/expense.py` - Expense model
6. `app/models/expense_split.py` - ExpenseSplit model
7. `app/models/settlement.py` - SettlementBatch and Settlement models with enum status
8. `app/models/activity_log.py` - ActivityLog model
9. `app/models/idempotency_key.py` - IdempotencyKey model
10. `app/models/__init__.py` - Clean exports of all models and enums
11. `app/tests/test_models.py` - Integration tests for all models
12. `app/tests/conftest.py` - Pytest fixtures for database sessions

### Modified Files:
1. `alembic/env.py` - Updated to use `Base.metadata` from models

## Tricky Mapping Notes

### 1. UUID Primary Keys
- All models use `UUID(as_uuid=True)` for primary keys
- Server default: `"uuid_generate_v4()"` (string, not function call)
- Example: `id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, server_default="uuid_generate_v4()")`

### 2. CITEXT for Email
- User.email uses `CITEXT()` for case-insensitive email storage
- Requires PostgreSQL `citext` extension (created in migration)
- Example: `email: Mapped[str] = mapped_column(CITEXT(), unique=True, nullable=False)`

### 3. BIGINT for Cents
- All monetary values use `BigInteger()` (maps to PostgreSQL `bigint`)
- Examples: `amount_cents`, `share_cents` in Expense, ExpenseSplit, Settlement
- No floats/decimals per non-negotiables

### 4. Timestamptz Mapping
- All timestamp fields use `TIMESTAMP(timezone=True)` for PostgreSQL `timestamptz`
- Server default: `func.now()` (SQLAlchemy function, not string)
- Fields: `created_at`, `updated_at` in User, Group, Expense, SettlementBatch
- Example: `created_at: Mapped[datetime] = mapped_column(TIMESTAMP(timezone=True), server_default=func.now(), nullable=False)`

### 5. Enum Types
- **MembershipRole**: `SQLEnum(MembershipRole, name="membership_role")`
  - Values: `OWNER`, `MEMBER`, `VIEWER`
- **SettlementStatus**: `SQLEnum(SettlementStatus, name="settlement_status")`
  - Values: `SUGGESTED`, `PAID`, `VOIDED`
- Both enums are Python `str, enum.Enum` subclasses for JSON serialization

### 6. Composite Foreign Keys
- Some FKs are composite (e.g., `(group_id, paid_by)` -> `(memberships.group_id, memberships.id)`)
- These are handled at DB level via deferred constraints
- SQLAlchemy relationships don't directly support composite FKs, so we use regular FKs where possible
- Composite FK constraints are enforced by the database migration

### 7. JSONB Fields
- `ActivityLog.metadata` and `IdempotencyKey.response_body` use `JSONB()`
- Maps to PostgreSQL `jsonb` type
- Python type: `Mapped[dict | None]`

### 8. Relationships
- All relationships use `back_populates` for bidirectional navigation
- Cascade deletes configured: `cascade="all, delete-orphan"` where appropriate
- Circular imports avoided using `TYPE_CHECKING` guards

### 9. Check Constraints
- `Expense.amount_cents > 0` enforced via `CheckConstraint`
- `ExpenseSplit.share_cents >= 0` enforced via `CheckConstraint`
- `Settlement.amount_cents > 0` and `from_membership <> to_membership` enforced

### 10. Unique Constraints
- Composite uniques: `(group_id, user_id)` on Membership, `(group_id, id)` on several tables
- Single column unique: `email` on User
- Triple unique: `(endpoint, user_id, request_hash)` on IdempotencyKey

## Running Tests

Tests require a running Postgres database (via docker-compose):

```bash
# Start database
docker-compose up -d db

# Run migrations
cd backend
alembic upgrade head

# Run tests
pytest app/tests/test_models.py -v
```

Tests use transactions that rollback after each test, so they're safe to run against a real database.

## Model Relationships Summary

- **User** ↔ **Membership** (one-to-many)
- **Group** ↔ **Membership** (one-to-many, back_populates)
- **Group** ↔ **Expense** (one-to-many, back_populates)
- **Group** ↔ **SettlementBatch** (one-to-many, back_populates)
- **Group** ↔ **ActivityLog** (one-to-many, back_populates)
- **Expense** ↔ **ExpenseSplit** (one-to-many, back_populates)
- **SettlementBatch** ↔ **Settlement** (one-to-many, back_populates)
- **Membership** ↔ **Expense** (via paid_by, composite FK at DB level)
- **Membership** ↔ **ExpenseSplit** (one-to-many)
- **Membership** ↔ **Settlement** (via from_membership/to_membership, composite FK at DB level)

