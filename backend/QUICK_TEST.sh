#!/bin/bash
# Quick API test script

BASE_URL="http://localhost:8000"

echo "=== Quick API Test ==="
echo ""

# 1. Health check
echo "1. Health Check"
curl -s "$BASE_URL/health" | jq '.' 2>/dev/null || curl -s "$BASE_URL/health"
echo ""
echo ""

# 2. Signup
echo "2. Signup"
SIGNUP_EMAIL="test$(date +%s)@example.com"
SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$SIGNUP_EMAIL\", \"password\": \"password123\"}")

echo "$SIGNUP_RESPONSE" | jq '.' 2>/dev/null || echo "$SIGNUP_RESPONSE"

# Extract token (jq or grep)
if command -v jq &> /dev/null; then
    TOKEN=$(echo "$SIGNUP_RESPONSE" | jq -r '.access_token // empty')
else
    TOKEN=$(echo "$SIGNUP_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo ""
    echo "❌ Signup failed!"
    echo "Check server logs for errors"
    exit 1
fi

echo ""
echo "✓ Signup successful"
echo "Token: ${TOKEN:0:30}..."
echo ""

# 3. Get current user
echo "3. Get Current User"
curl -s -X GET "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN" | jq '.' 2>/dev/null || \
curl -s -X GET "$BASE_URL/auth/me" \
  -H "Authorization: Bearer $TOKEN"
echo ""
echo ""

# 4. Create group
echo "4. Create Group"
GROUP_RESPONSE=$(curl -s -X POST "$BASE_URL/groups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Group", "currency": "USD"}')

if command -v jq &> /dev/null; then
    GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.id // empty')
    echo "$GROUP_RESPONSE" | jq '.'
else
    GROUP_ID=$(echo "$GROUP_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo "$GROUP_RESPONSE"
fi

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" = "null" ]; then
    echo "❌ Create group failed!"
    exit 1
fi

echo "✓ Group created: $GROUP_ID"
echo ""

# 5. Get members
echo "5. Get Group Members"
MEMBERS_RESPONSE=$(curl -s -X GET "$BASE_URL/groups/$GROUP_ID/members" \
  -H "Authorization: Bearer $TOKEN")

if command -v jq &> /dev/null; then
    MEMBERSHIP_ID=$(echo "$MEMBERS_RESPONSE" | jq -r '.[0].id // empty')
    echo "$MEMBERS_RESPONSE" | jq '.'
else
    MEMBERSHIP_ID=$(echo "$MEMBERS_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo "$MEMBERS_RESPONSE"
fi

if [ -z "$MEMBERSHIP_ID" ] || [ "$MEMBERSHIP_ID" = "null" ]; then
    echo "❌ Get members failed!"
    exit 1
fi

echo "✓ Membership ID: $MEMBERSHIP_ID"
echo ""

# 6. Create expense
echo "6. Create Expense"
EXPENSE_RESPONSE=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/expenses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"title\": \"Test Dinner\",
    \"amount_cents\": 1000,
    \"currency\": \"USD\",
    \"paid_by\": \"$MEMBERSHIP_ID\",
    \"expense_date\": \"$(date +%Y-%m-%d)\",
    \"split_among\": [\"$MEMBERSHIP_ID\"]
  }")

if command -v jq &> /dev/null; then
    EXPENSE_ID=$(echo "$EXPENSE_RESPONSE" | jq -r '.id // empty')
    echo "$EXPENSE_RESPONSE" | jq '.'
else
    EXPENSE_ID=$(echo "$EXPENSE_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    echo "$EXPENSE_RESPONSE"
fi

if [ -z "$EXPENSE_ID" ] || [ "$EXPENSE_ID" = "null" ]; then
    echo "❌ Create expense failed!"
    exit 1
fi

echo "✓ Expense created: $EXPENSE_ID"
echo ""

# 7. List expenses
echo "7. List Group Expenses"
curl -s -X GET "$BASE_URL/groups/$GROUP_ID/expenses" \
  -H "Authorization: Bearer $TOKEN" | jq '.' 2>/dev/null || \
curl -s -X GET "$BASE_URL/groups/$GROUP_ID/expenses" \
  -H "Authorization: Bearer $TOKEN"
echo ""
echo ""

echo "=== All Tests Passed! ==="

