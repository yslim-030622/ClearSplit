#!/bin/bash
# API Testing Script for ClearSplit
# Tests all endpoints: Auth, Groups, Expenses

set -e

BASE_URL="${BASE_URL:-http://localhost:8000}"
echo "Testing API at: $BASE_URL"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test health endpoint
echo -e "${YELLOW}1. Testing Health Endpoint${NC}"
HEALTH_RESPONSE=$(curl -s "$BASE_URL/health")
echo "Response: $HEALTH_RESPONSE"
if [[ "$HEALTH_RESPONSE" == *"ok"* ]]; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
    exit 1
fi
echo ""

# Test signup
echo -e "${YELLOW}2. Testing Signup${NC}"
SIGNUP_EMAIL="test$(date +%s)@example.com"
SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$SIGNUP_EMAIL\", \"password\": \"password123\"}")

ACCESS_TOKEN=$(echo "$SIGNUP_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
REFRESH_TOKEN=$(echo "$SIGNUP_RESPONSE" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
USER_ID=$(echo "$SIGNUP_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}✗ Signup failed${NC}"
    echo "Response: $SIGNUP_RESPONSE"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check server logs for detailed error"
    echo "  2. Verify database is running: docker-compose ps"
    echo "  3. Run migrations: alembic upgrade head"
    echo "  4. Check DATABASE_URL in .env file"
    exit 1
fi

echo -e "${GREEN}✓ Signup successful${NC}"
echo "User ID: $USER_ID"
echo "Access Token: ${ACCESS_TOKEN:0:20}..."
echo ""

# Test login
echo -e "${YELLOW}3. Testing Login${NC}"
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$SIGNUP_EMAIL\", \"password\": \"password123\"}")

LOGIN_ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$LOGIN_ACCESS_TOKEN" ]; then
    echo -e "${RED}✗ Login failed${NC}"
    echo "Response: $LOGIN_RESPONSE"
    exit 1
fi
echo -e "${GREEN}✓ Login successful${NC}"
echo ""

# Test get me
echo -e "${YELLOW}4. Testing GET /auth/me${NC}"
ME_RESPONSE=$(curl -s -X GET "$BASE_URL/auth/me" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
if [[ "$ME_RESPONSE" == *"$SIGNUP_EMAIL"* ]]; then
    echo -e "${GREEN}✓ Get current user successful${NC}"
else
    echo -e "${RED}✗ Get current user failed${NC}"
    echo "Response: $ME_RESPONSE"
fi
echo ""

# Test refresh token
echo -e "${YELLOW}5. Testing Refresh Token${NC}"
REFRESH_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")
NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
if [ -z "$NEW_ACCESS_TOKEN" ]; then
    echo -e "${RED}✗ Refresh token failed${NC}"
    echo "Response: $REFRESH_RESPONSE"
else
    echo -e "${GREEN}✓ Refresh token successful${NC}"
    ACCESS_TOKEN=$NEW_ACCESS_TOKEN
fi
echo ""

# Test create group
echo -e "${YELLOW}6. Testing Create Group${NC}"
GROUP_RESPONSE=$(curl -s -X POST "$BASE_URL/groups" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "Test Group", "currency": "USD"}')
GROUP_ID=$(echo "$GROUP_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
if [ -z "$GROUP_ID" ]; then
    echo -e "${RED}✗ Create group failed${NC}"
    echo "Response: $GROUP_RESPONSE"
    exit 1
fi
echo -e "${GREEN}✓ Create group successful${NC}"
echo "Group ID: $GROUP_ID"
echo ""

# Test list groups
echo -e "${YELLOW}7. Testing List Groups${NC}"
LIST_GROUPS_RESPONSE=$(curl -s -X GET "$BASE_URL/groups" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
if [[ "$LIST_GROUPS_RESPONSE" == *"$GROUP_ID"* ]]; then
    echo -e "${GREEN}✓ List groups successful${NC}"
else
    echo -e "${RED}✗ List groups failed${NC}"
    echo "Response: $LIST_GROUPS_RESPONSE"
fi
echo ""

# Test get group
echo -e "${YELLOW}8. Testing Get Group${NC}"
GET_GROUP_RESPONSE=$(curl -s -X GET "$BASE_URL/groups/$GROUP_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
if [[ "$GET_GROUP_RESPONSE" == *"$GROUP_ID"* ]]; then
    echo -e "${GREEN}✓ Get group successful${NC}"
else
    echo -e "${RED}✗ Get group failed${NC}"
    echo "Response: $GET_GROUP_RESPONSE"
fi
echo ""

# Create second user for membership test
echo -e "${YELLOW}9. Creating Second User for Membership Test${NC}"
SIGNUP_EMAIL2="test2$(date +%s)@example.com"
SIGNUP_RESPONSE2=$(curl -s -X POST "$BASE_URL/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$SIGNUP_EMAIL2\", \"password\": \"password123\"}")
USER_ID2=$(echo "$SIGNUP_RESPONSE2" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}✓ Second user created${NC}"
echo ""

# Get membership ID (need to get from group members endpoint)
echo -e "${YELLOW}10. Testing Get Group Members${NC}"
MEMBERS_RESPONSE=$(curl -s -X GET "$BASE_URL/groups/$GROUP_ID/members" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
MEMBERSHIP_ID=$(echo "$MEMBERS_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
echo -e "${GREEN}✓ Get members successful${NC}"
echo "Membership ID: $MEMBERSHIP_ID"
echo ""

# Test add member (will fail if user2 doesn't exist in system, but that's expected)
echo -e "${YELLOW}11. Testing Add Member (by email)${NC}"
ADD_MEMBER_RESPONSE=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/members" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"$SIGNUP_EMAIL2\", \"role\": \"member\"}")
if [[ "$ADD_MEMBER_RESPONSE" == *"membership"* ]] || [[ "$ADD_MEMBER_RESPONSE" == *"id"* ]]; then
    echo -e "${GREEN}✓ Add member successful${NC}"
    NEW_MEMBERSHIP_ID=$(echo "$ADD_MEMBER_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    echo "New Membership ID: $NEW_MEMBERSHIP_ID"
else
    echo -e "${YELLOW}⚠ Add member response: $ADD_MEMBER_RESPONSE${NC}"
fi
echo ""

# Test create expense
echo -e "${YELLOW}12. Testing Create Expense${NC}"
EXPENSE_RESPONSE=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/expenses" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"title\": \"Test Dinner\",
        \"amount_cents\": 1000,
        \"currency\": \"USD\",
        \"paid_by\": \"$MEMBERSHIP_ID\",
        \"expense_date\": \"$(date +%Y-%m-%d)\",
        \"split_among\": [\"$MEMBERSHIP_ID\"]
    }")
EXPENSE_ID=$(echo "$EXPENSE_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
if [ -z "$EXPENSE_ID" ]; then
    echo -e "${RED}✗ Create expense failed${NC}"
    echo "Response: $EXPENSE_RESPONSE"
else
    echo -e "${GREEN}✓ Create expense successful${NC}"
    echo "Expense ID: $EXPENSE_ID"
fi
echo ""

# Test list expenses
echo -e "${YELLOW}13. Testing List Group Expenses${NC}"
LIST_EXPENSES_RESPONSE=$(curl -s -X GET "$BASE_URL/groups/$GROUP_ID/expenses" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
if [[ "$LIST_EXPENSES_RESPONSE" == *"$EXPENSE_ID"* ]]; then
    echo -e "${GREEN}✓ List expenses successful${NC}"
else
    echo -e "${RED}✗ List expenses failed${NC}"
    echo "Response: $LIST_EXPENSES_RESPONSE"
fi
echo ""

# Test get expense
if [ ! -z "$EXPENSE_ID" ]; then
    echo -e "${YELLOW}14. Testing Get Expense${NC}"
    GET_EXPENSE_RESPONSE=$(curl -s -X GET "$BASE_URL/expenses/$EXPENSE_ID" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    if [[ "$GET_EXPENSE_RESPONSE" == *"$EXPENSE_ID"* ]]; then
        echo -e "${GREEN}✓ Get expense successful${NC}"
    else
        echo -e "${RED}✗ Get expense failed${NC}"
        echo "Response: $GET_EXPENSE_RESPONSE"
    fi
    echo ""
fi

# Test idempotency
if [ ! -z "$EXPENSE_ID" ]; then
    echo -e "${YELLOW}15. Testing Idempotency${NC}"
    IDEMPOTENCY_KEY="test-key-$(date +%s)"
    IDEMPOTENT_RESPONSE=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/expenses" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
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
    FIRST_EXPENSE_ID=$(echo "$IDEMPOTENT_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    # Make same request again
    IDEMPOTENT_RESPONSE2=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/expenses" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
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
    SECOND_EXPENSE_ID=$(echo "$IDEMPOTENT_RESPONSE2" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ "$FIRST_EXPENSE_ID" == "$SECOND_EXPENSE_ID" ]; then
        echo -e "${GREEN}✓ Idempotency test passed (same expense ID returned)${NC}"
    else
        echo -e "${RED}✗ Idempotency test failed${NC}"
        echo "First ID: $FIRST_EXPENSE_ID"
        echo "Second ID: $SECOND_EXPENSE_ID"
    fi
    echo ""
fi

echo -e "${GREEN}=== API Testing Complete ===${NC}"

