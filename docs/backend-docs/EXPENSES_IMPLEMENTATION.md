# Phase 3 Expenses Implementation (MVP - Equal Split Only)

## Overview

Phase 3 expenses endpoints with equal split support. All expenses are split equally among specified members, with remainder distributed to the first members in the list.

## Files Created/Modified

### Created Files:
1. `app/services/expense.py` - Expense business logic with equal split calculation
2. `app/core/idempotency.py` - Idempotency key handling utilities
3. `app/api/expenses.py` - Expenses API routes
4. `app/tests/test_expenses.py` - Expenses tests

### Modified Files:
1. `app/schemas/expense.py` - Added `ExpenseCreateEqualSplit` schema for MVP
2. `app/main.py` - Added expenses router and GET /expenses/{expense_id} route

## Equal Split Remainder Rule

When splitting an expense equally, if the amount doesn't divide evenly:

**Rule:** The remainder (amount_cents % num_splits) is distributed to the first members in the `split_among` list.

**Examples:**
- 1000 cents / 3 people = [334, 333, 333] (first person gets +1)
- 100 cents / 3 people = [34, 33, 33] (first person gets +1)
- 1000 cents / 2 people = [500, 500] (no remainder)
- 1 cent / 3 people = [1, 0, 0] (first person gets all)

**Implementation:**
```python
base_share = amount_cents // num_splits
remainder = amount_cents % num_splits
# First 'remainder' people get base_share + 1, rest get base_share
splits = [base_share + 1] * remainder + [base_share] * (num_splits - remainder)
```

This ensures:
- All splits sum to exactly `amount_cents`
- Distribution is fair (difference is at most 1 cent)
- Remainder goes to first members (deterministic)

## API Endpoints

### POST /groups/{group_id}/expenses
Create a new expense with equal splits.

**Authentication:** Required

**Headers:**
- `Idempotency-Key` (optional): UUID string for idempotent requests

**Request:**
```json
{
  "title": "Dinner",
  "amount_cents": 1000,
  "currency": "USD",
  "paid_by": "membership-uuid",
  "expense_date": "2024-01-15",
  "split_among": ["membership-uuid-1", "membership-uuid-2", "membership-uuid-3"],
  "memo": "Optional memo"
}
```

**Response:** 201 Created
```json
{
  "id": "expense-uuid",
  "group_id": "group-uuid",
  "title": "Dinner",
  "amount_cents": 1000,
  "currency": "USD",
  "paid_by": "membership-uuid",
  "expense_date": "2024-01-15",
  "memo": "Optional memo",
  "version": 1,
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-15T12:00:00Z",
  "splits": [
    {
      "id": "split-uuid-1",
      "expense_id": "expense-uuid",
      "membership_id": "membership-uuid-1",
      "share_cents": 334,
      "created_at": "2024-01-15T12:00:00Z"
    },
    {
      "id": "split-uuid-2",
      "expense_id": "expense-uuid",
      "membership_id": "membership-uuid-2",
      "share_cents": 333,
      "created_at": "2024-01-15T12:00:00Z"
    },
    {
      "id": "split-uuid-3",
      "expense_id": "expense-uuid",
      "membership_id": "membership-uuid-3",
      "share_cents": 333,
      "created_at": "2024-01-15T12:00:00Z"
    }
  ]
}
```

**Validation:**
- Payer (`paid_by`) must be a membership in the group
- All memberships in `split_among` must be in the group
- Amount must be > 0
- At least one member in `split_among`

**Errors:**
- 403: User is not a member of the group
- 400: Payer or split members not in group, invalid request
- 201: Success (idempotent requests return same response)

### GET /groups/{group_id}/expenses
List all expenses for a group.

**Authentication:** Required

**Response:** 200 OK
```json
[
  {
    "id": "expense-uuid",
    "group_id": "group-uuid",
    "title": "Dinner",
    "amount_cents": 1000,
    "currency": "USD",
    "paid_by": "membership-uuid",
    "expense_date": "2024-01-15",
    "memo": null,
    "version": 1,
    "created_at": "2024-01-15T12:00:00Z",
    "updated_at": "2024-01-15T12:00:00Z",
    "splits": [...]
  }
]
```

**Errors:**
- 403: User is not a member of the group

### GET /expenses/{expense_id}
Get a specific expense by ID.

**Authentication:** Required

**Response:** 200 OK
```json
{
  "id": "expense-uuid",
  "group_id": "group-uuid",
  "title": "Dinner",
  "amount_cents": 1000,
  "currency": "USD",
  "paid_by": "membership-uuid",
  "expense_date": "2024-01-15",
  "memo": null,
  "version": 1,
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-15T12:00:00Z",
  "splits": [...]
}
```

**Errors:**
- 404: Expense not found
- 403: User is not a member of the expense's group

## Idempotency

Expense creation supports idempotency via the `Idempotency-Key` header.

**How it works:**
1. Client sends `Idempotency-Key: <uuid>` header with request
2. Server computes hash of request body
3. Server checks if `(endpoint, user_id, request_hash)` exists in `idempotency_keys` table
4. If exists: Return cached response (same expense ID)
5. If not: Create expense, store response in `idempotency_keys` table

**Key points:**
- Idempotency key is per-user (same key for different users = different requests)
- Request body hash ensures same request = same response
- Response is cached in database (JSONB)
- Subsequent requests with same key return cached response

**Example:**
```bash
# First request
curl -X POST http://localhost:8000/groups/{group_id}/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: abc-123-def" \
  -H "Content-Type: application/json" \
  -d '{...}'
# Returns: expense-uuid-1

# Second request (same key, same body)
curl -X POST http://localhost:8000/groups/{group_id}/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: abc-123-def" \
  -H "Content-Type: application/json" \
  -d '{...}'
# Returns: expense-uuid-1 (same, no duplicate created)
```

## Transactions

Expense creation is atomic:
- Expense row created
- All split rows created
- All in single database transaction
- If any step fails, entire operation rolls back

This ensures:
- No orphaned expenses without splits
- No orphaned splits without expenses
- Database constraint `enforce_expense_split_sum` validates splits sum = amount

## Testing

Run tests:
```bash
cd backend
pytest app/tests/test_expenses.py -v
```

Test coverage:
- ✅ Create expense with equal splits
- ✅ Equal split remainder distribution
- ✅ Idempotent double submit returns same result
- ✅ Invalid payer (not in group)
- ✅ Invalid split member (not in group)
- ✅ List group expenses
- ✅ Get expense by ID
- ✅ Get expense when not a member (403)
- ✅ Calculate equal splits function

## Sample curl Commands

### Prerequisites
```bash
# Login and get token
TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password123"}' \
  | jq -r '.access_token')

# Get group ID (from previous group creation)
GROUP_ID="<group-uuid>"
```

### 1. Create Expense (Equal Split)
```bash
curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Dinner",
    "amount_cents": 1000,
    "currency": "USD",
    "paid_by": "<membership-uuid>",
    "expense_date": "2024-01-15",
    "split_among": ["<membership-uuid-1>", "<membership-uuid-2>", "<membership-uuid-3>"]
  }'
```

### 2. Create Expense with Idempotency Key
```bash
IDEMPOTENCY_KEY=$(uuidgen)

curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Lunch",
    "amount_cents": 1500,
    "currency": "USD",
    "paid_by": "<membership-uuid>",
    "expense_date": "2024-01-15",
    "split_among": ["<membership-uuid-1>", "<membership-uuid-2>"]
  }'

# Repeat same request - should return same expense ID
curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Lunch",
    "amount_cents": 1500,
    "currency": "USD",
    "paid_by": "<membership-uuid>",
    "expense_date": "2024-01-15",
    "split_among": ["<membership-uuid-1>", "<membership-uuid-2>"]
  }'
```

### 3. List Group Expenses
```bash
curl -X GET http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN"
```

### 4. Get Expense by ID
```bash
EXPENSE_ID="<expense-uuid>"

curl -X GET http://localhost:8000/expenses/$EXPENSE_ID \
  -H "Authorization: Bearer $TOKEN"
```

### 5. Test Remainder Distribution
```bash
# Create expense with amount that doesn't divide evenly
# 1000 cents / 3 people = 334, 333, 333
curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Coffee",
    "amount_cents": 1000,
    "currency": "USD",
    "paid_by": "<membership-uuid>",
    "expense_date": "2024-01-15",
    "split_among": ["<membership-uuid-1>", "<membership-uuid-2>", "<membership-uuid-3>"]
  }'
# Check splits: first person gets 334, others get 333
```

## Error Responses

### 400 Bad Request
```json
{
  "detail": "Payer membership not found in group"
}
```
or
```json
{
  "detail": "Memberships not found in group: {<uuid>}"
}
```

### 403 Forbidden
```json
{
  "detail": "You are not a member of this group"
}
```
or
```json
{
  "detail": "You are not a member of this expense's group"
}
```

### 404 Not Found
```json
{
  "detail": "Expense not found"
}
```

## Implementation Notes

1. **Equal Split Only**: MVP only supports equal splits. Custom splits will be added in future phases.

2. **Atomic Transactions**: Expense + splits created in single transaction via `create_expense_with_equal_splits`.

3. **Idempotency**: Request body hash ensures same request = same response. Key is per-user.

4. **Validation**: Payer and all split members must be in the group (validated before creation).

5. **Remainder Rule**: Deterministic - first members in list get remainder cents.

6. **Database Constraints**: Database trigger `enforce_expense_split_sum` ensures splits sum = amount.

