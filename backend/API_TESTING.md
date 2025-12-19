# API Testing Guide

This guide provides comprehensive instructions for testing all ClearSplit API endpoints.

## Prerequisites

1. **Start the database:**
   ```bash
   docker-compose up -d db
   ```

2. **Run migrations:**
   ```bash
   cd backend
   source .venv/bin/activate
   alembic upgrade head
   ```

3. **Start the server:**
   ```bash
   make run
   ```
   The server should be running on `http://localhost:8000`.

## Quick Test

Run the automated test script:

```bash
cd backend
./test_api.sh
```

This script tests all endpoints automatically and reports results.

## Manual Testing

### Step 1: Health Check

```bash
curl http://localhost:8000/health
```

**Expected Response:**
```json
{"status":"ok"}
```

### Step 2: User Signup

```bash
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password123"
  }'
```

**Expected Response:** 201 Created
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

**Save the access token for subsequent requests:**
```bash
TOKEN=$(curl -s -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "user2@example.com", "password": "password123"}' \
  | jq -r '.access_token')
```

### Step 3: User Login

```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "password123"
  }'
```

### Step 4: Get Current User

```bash
curl -X GET http://localhost:8000/auth/me \
  -H "Authorization: Bearer $TOKEN"
```

### Step 5: Refresh Token

```bash
curl -X POST http://localhost:8000/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refresh_token": "<refresh_token_from_signup>"
  }'
```

### Step 6: Create Group

```bash
GROUP_RESPONSE=$(curl -s -X POST http://localhost:8000/groups \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Weekend Trip",
    "currency": "USD"
  }')

GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.id')
echo "Group ID: $GROUP_ID"
```

### Step 7: List My Groups

```bash
curl -X GET http://localhost:8000/groups \
  -H "Authorization: Bearer $TOKEN"
```

### Step 8: Get Group Details

```bash
curl -X GET http://localhost:8000/groups/$GROUP_ID \
  -H "Authorization: Bearer $TOKEN"
```

### Step 9: Get Group Members

```bash
MEMBERS_RESPONSE=$(curl -s -X GET http://localhost:8000/groups/$GROUP_ID/members \
  -H "Authorization: Bearer $TOKEN")

MEMBERSHIP_ID=$(echo "$MEMBERS_RESPONSE" | jq -r '.[0].id')
echo "Membership ID: $MEMBERSHIP_ID"
```

### Step 10: Add Member to Group

First, create a second user:

```bash
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email": "friend@example.com", "password": "password123"}'
```

Then add them to the group:

```bash
curl -X POST http://localhost:8000/groups/$GROUP_ID/members \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "friend@example.com",
    "role": "member"
  }'
```

### Step 11: Create Expense (Equal Split)

```bash
curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Dinner\",
    \"amount_cents\": 1000,
    \"currency\": \"USD\",
    \"paid_by\": \"$MEMBERSHIP_ID\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [\"$MEMBERSHIP_ID\"]
  }"
```

**Expected Response:** 201 Created
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
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-15T12:00:00Z",
  "version": 1,
  "splits": [
    {
      "id": "split-uuid",
      "expense_id": "expense-uuid",
      "membership_id": "membership-uuid",
      "share_cents": 1000,
      "created_at": "2024-01-15T12:00:00Z"
    }
  ]
}
```

### Step 12: Test Equal Split Remainder

Create an expense that doesn't divide evenly:

```bash
# Get all membership IDs first (add more members if needed)
MEMBERS_RESPONSE=$(curl -s -X GET http://localhost:8000/groups/$GROUP_ID/members \
  -H "Authorization: Bearer $TOKEN")

# Extract all membership IDs
MEMBERSHIP_IDS=$(echo "$MEMBERS_RESPONSE" | jq -r '.[].id' | tr '\n' ',' | sed 's/,$//')

# Create expense with 1000 cents split among 3 people
curl -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Coffee\",
    \"amount_cents\": 1000,
    \"currency\": \"USD\",
    \"paid_by\": \"$(echo "$MEMBERS_RESPONSE" | jq -r '.[0].id')\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [
      \"$(echo "$MEMBERS_RESPONSE" | jq -r '.[0].id')\",
      \"$(echo "$MEMBERS_RESPONSE" | jq -r '.[1].id')\",
      \"$(echo "$MEMBERS_RESPONSE" | jq -r '.[2].id')\"
    ]
  }"
```

**Expected splits:** `[334, 333, 333]` (first person gets +1 cent remainder)

### Step 13: Test Idempotency

```bash
IDEMPOTENCY_KEY="test-key-$(date +%s)"

# First request
RESPONSE1=$(curl -s -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Idempotent Test\",
    \"amount_cents\": 500,
    \"currency\": \"USD\",
    \"paid_by\": \"$MEMBERSHIP_ID\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [\"$MEMBERSHIP_ID\"]
  }")

EXPENSE_ID1=$(echo "$RESPONSE1" | jq -r '.id')
echo "First Expense ID: $EXPENSE_ID1"

# Second request (same key, same body)
RESPONSE2=$(curl -s -X POST http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN" \
  -H "Idempotency-Key: $IDEMPOTENCY_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Idempotent Test\",
    \"amount_cents\": 500,
    \"currency\": \"USD\",
    \"paid_by\": \"$MEMBERSHIP_ID\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [\"$MEMBERSHIP_ID\"]
  }")

EXPENSE_ID2=$(echo "$RESPONSE2" | jq -r '.id')
echo "Second Expense ID: $EXPENSE_ID2"

# Verify they are the same
if [ "$EXPENSE_ID1" == "$EXPENSE_ID2" ]; then
  echo "✓ Idempotency test passed - Same expense ID returned"
else
  echo "✗ Idempotency test failed - Different IDs"
fi
```

### Step 14: List Group Expenses

```bash
curl -X GET http://localhost:8000/groups/$GROUP_ID/expenses \
  -H "Authorization: Bearer $TOKEN"
```

### Step 15: Get Expense Details

```bash
EXPENSE_ID="<expense-uuid-from-previous-step>"

curl -X GET http://localhost:8000/expenses/$EXPENSE_ID \
  -H "Authorization: Bearer $TOKEN"
```

## Using FastAPI Interactive Documentation

The easiest way to test the API is using the interactive Swagger UI:

1. Open your browser and navigate to: http://localhost:8000/docs
2. Click "Authorize" and enter your access token
3. Try out any endpoint using the "Try it out" button
4. View request/response examples

Alternatively, use ReDoc at: http://localhost:8000/redoc

## Error Testing

### Invalid Login

```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "wrongpassword"
  }'
```

**Expected:** 401 Unauthorized

### Access Without Token

```bash
curl -X GET http://localhost:8000/groups
```

**Expected:** 403 Forbidden

### Access to Non-Member Group

```bash
# Login as different user, try to access group
curl -X GET http://localhost:8000/groups/<group_id> \
  -H "Authorization: Bearer <other_user_token>"
```

**Expected:** 403 Forbidden

## Test Scripts

### Full Test Suite

```bash
./test_api.sh
```

Tests all endpoints with comprehensive checks.

### Quick Test

```bash
./QUICK_TEST.sh
```

Quick smoke test of main endpoints.

## Common Issues

### Database Connection Error

If you see `role "clearsplit" does not exist`:

1. Check that the database container is running: `docker-compose ps`
2. Verify `.env` file has correct `DATABASE_URL`:
   ```
   DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit
   ```
3. Run migrations: `alembic upgrade head`

### Migration Errors

If migrations fail:

1. Check database is accessible: `docker exec -it clearsplit-db-1 psql -U clearsplit -d clearsplit -c "SELECT 1;"`
2. Verify Alembic version: `alembic current`
3. Check migration files exist: `ls alembic/versions/`

### Server Not Starting

1. Check port 8000 is available: `lsof -i :8000`
2. Review server logs for import errors
3. Verify all dependencies installed: `pip install -r requirements.txt`

## Example Complete Flow

```bash
#!/bin/bash
# Complete API test flow

BASE_URL="http://localhost:8000"

# 1. Signup
TOKEN=$(curl -s -X POST "$BASE_URL/auth/signup" \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "password123"}' \
  | jq -r '.access_token')

# 2. Create Group
GROUP_ID=$(curl -s -X POST "$BASE_URL/groups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Group", "currency": "USD"}' \
  | jq -r '.id')

# 3. Get Membership
MEMBERSHIP_ID=$(curl -s -X GET "$BASE_URL/groups/$GROUP_ID/members" \
  -H "Authorization: Bearer $TOKEN" \
  | jq -r '.[0].id')

# 4. Create Expense
EXPENSE_ID=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/expenses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Test Expense\",
    \"amount_cents\": 1000,
    \"currency\": \"USD\",
    \"paid_by\": \"$MEMBERSHIP_ID\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [\"$MEMBERSHIP_ID\"]
  }" | jq -r '.id')

echo "✓ Created expense: $EXPENSE_ID"

# 5. List Expenses
curl -s -X GET "$BASE_URL/groups/$GROUP_ID/expenses" \
  -H "Authorization: Bearer $TOKEN" | jq '.'
```

## Next Steps

After testing the API:

1. Review the implementation documentation:
   - `AUTH_IMPLEMENTATION.md` - Authentication details
   - `GROUPS_IMPLEMENTATION.md` - Groups and memberships
   - `EXPENSES_IMPLEMENTATION.md` - Expenses and splits

2. Run unit tests:
   ```bash
   pytest app/tests/ -v
   ```

3. Check code coverage:
   ```bash
   pytest --cov=app app/tests/
   ```

