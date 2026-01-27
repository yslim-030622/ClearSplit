#!/bin/bash

# Comprehensive Backend Test Script
# Tests all major functionality including Shopping Sessions

set -e  # Exit on error

BASE_URL="http://localhost:8000"
echo "Testing ClearSplit Backend at $BASE_URL"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

test_endpoint() {
    local name=$1
    local method=$2
    local endpoint=$3
    local data=$4
    local headers=$5
    local expected_status=$6
    
    echo -e "${BLUE}Testing: $name${NC}"
    
    if [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            $headers \
            -d "$data")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            $headers)
    fi
    
    body=$(echo "$response" | sed '$d')
    status=$(echo "$response" | tail -n 1)
    
    if [ "$status" == "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED${NC} (HTTP $status)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
    else
        echo -e "${RED}✗ FAILED${NC} (Expected $expected_status, got $status)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "$body"
    fi
    echo ""
}

# 1. Health Check
echo "=== 1. HEALTH CHECK ==="
test_endpoint "Health endpoint" "GET" "/health" "" "" "200"

# 2. Authentication Tests
echo "=== 2. AUTHENTICATION ==="

# Generate unique email for testing
TEST_EMAIL="test_$(date +%s)@example.com"
TEST_PASSWORD="SecurePass123!"

# Signup
echo "Signing up with: $TEST_EMAIL"
SIGNUP_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/signup" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")

ACCESS_TOKEN=$(echo "$SIGNUP_RESPONSE" | jq -r '.access_token')
USER_ID=$(echo "$SIGNUP_RESPONSE" | jq -r '.user.id')

if [ "$ACCESS_TOKEN" != "null" ]; then
    echo -e "${GREEN}✓ Signup successful${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "User ID: $USER_ID"
    echo "Token: ${ACCESS_TOKEN:0:20}..."
else
    echo -e "${RED}✗ Signup failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$SIGNUP_RESPONSE"
    exit 1
fi
echo ""

# Test /auth/me
test_endpoint "Get current user" "GET" "/auth/me" "" "-H \"Authorization: Bearer $ACCESS_TOKEN\"" "200"

# 3. Groups Tests
echo "=== 3. GROUPS ==="

# Create a group
echo "Creating test group..."
GROUP_RESPONSE=$(curl -s -X POST "$BASE_URL/groups" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d '{"name":"Test Grocery Group","currency":"USD"}')

GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.id')
MEMBERSHIP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.user_membership_id')

if [ "$GROUP_ID" != "null" ]; then
    echo -e "${GREEN}✓ Group created${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Group ID: $GROUP_ID"
    echo "Membership ID: $MEMBERSHIP_ID"
else
    echo -e "${RED}✗ Group creation failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$GROUP_RESPONSE"
    exit 1
fi
echo ""

# List groups
test_endpoint "List user groups" "GET" "/groups" "" "-H \"Authorization: Bearer $ACCESS_TOKEN\"" "200"

# Get group members
test_endpoint "List group members" "GET" "/groups/$GROUP_ID/members" "" "-H \"Authorization: Bearer $ACCESS_TOKEN\"" "200"

# 4. Shopping Sessions Tests
echo "=== 4. SHOPPING SESSIONS ==="

# Create a shopping session
echo "Creating shopping session..."
SESSION_DATA="{
    \"title\":\"Costco Trip\",
    \"shopping_date\":\"2026-01-07\",
    \"paid_by_membership_id\":\"$MEMBERSHIP_ID\"
}"

SESSION_RESPONSE=$(curl -s -X POST "$BASE_URL/groups/$GROUP_ID/shopping-sessions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$SESSION_DATA")

SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.id')

if [ "$SESSION_ID" != "null" ]; then
    echo -e "${GREEN}✓ Shopping session created${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Session ID: $SESSION_ID"
else
    echo -e "${RED}✗ Shopping session creation failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$SESSION_RESPONSE"
    exit 1
fi
echo ""

# List shopping sessions
test_endpoint "List shopping sessions" "GET" "/groups/$GROUP_ID/shopping-sessions" "" "-H \"Authorization: Bearer $ACCESS_TOKEN\"" "200"

# Get specific session
test_endpoint "Get shopping session details" "GET" "/shopping-sessions/$SESSION_ID" "" "-H \"Authorization: Bearer $ACCESS_TOKEN\"" "200"

# Set participants
echo "Setting session participants..."
PARTICIPANTS_DATA="{\"membership_ids\":[\"$MEMBERSHIP_ID\"]}"

PARTICIPANTS_RESPONSE=$(curl -s -X PUT "$BASE_URL/shopping-sessions/$SESSION_ID/participants" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$PARTICIPANTS_DATA")

if echo "$PARTICIPANTS_RESPONSE" | jq -e '.participants' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Participants set successfully${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "$PARTICIPANTS_RESPONSE" | jq '.'
else
    echo -e "${RED}✗ Setting participants failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$PARTICIPANTS_RESPONSE"
fi
echo ""

# 5. Shopping Items Tests
echo "=== 5. SHOPPING ITEMS ==="

# Create item 1: Milk
echo "Creating item: Milk..."
ITEM1_DATA="{
    \"name\":\"Milk\",
    \"quantity\":2,
    \"unit_price_cents\":349,
    \"total_cents\":698
}"

ITEM1_RESPONSE=$(curl -s -X POST "$BASE_URL/shopping-sessions/$SESSION_ID/items" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$ITEM1_DATA")

ITEM1_ID=$(echo "$ITEM1_RESPONSE" | jq -r '.id')

if [ "$ITEM1_ID" != "null" ]; then
    echo -e "${GREEN}✓ Item created${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Item ID: $ITEM1_ID"
else
    echo -e "${RED}✗ Item creation failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$ITEM1_RESPONSE"
fi
echo ""

# Create item 2: Bread
echo "Creating item: Bread..."
ITEM2_DATA="{
    \"name\":\"Bread\",
    \"quantity\":1,
    \"total_cents\":299
}"

ITEM2_RESPONSE=$(curl -s -X POST "$BASE_URL/shopping-sessions/$SESSION_ID/items" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$ITEM2_DATA")

ITEM2_ID=$(echo "$ITEM2_RESPONSE" | jq -r '.id')

if [ "$ITEM2_ID" != "null" ]; then
    echo -e "${GREEN}✓ Item created${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Item ID: $ITEM2_ID"
else
    echo -e "${RED}✗ Item creation failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# 6. Set Item Sharers and Test Split Calculation
echo "=== 6. SPLIT CALCULATIONS ==="

echo "Setting sharers for Milk (should split $6.98 equally)..."
SHARERS_DATA="{\"membership_ids\":[\"$MEMBERSHIP_ID\"]}"

SHARERS_RESPONSE=$(curl -s -X PUT "$BASE_URL/items/$ITEM1_ID/sharers" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$SHARERS_DATA")

if echo "$SHARERS_RESPONSE" | jq -e '.splits' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Sharers set and splits calculated${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "Split details:"
    echo "$SHARERS_RESPONSE" | jq '.splits'
else
    echo -e "${RED}✗ Setting sharers failed${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "$SHARERS_RESPONSE"
fi
echo ""

# 7. Final Session Check
echo "=== 7. FINAL VERIFICATION ==="

echo "Getting complete session with all items and splits..."
FINAL_SESSION=$(curl -s -X GET "$BASE_URL/shopping-sessions/$SESSION_ID" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

echo "$FINAL_SESSION" | jq '.'
echo ""

# Check that items exist in session
ITEMS_COUNT=$(echo "$FINAL_SESSION" | jq '.items | length')
if [ "$ITEMS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Session contains $ITEMS_COUNT items${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}✗ Session has no items${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# 8. Test Summary
echo "========================================="
echo "TEST SUMMARY"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi

