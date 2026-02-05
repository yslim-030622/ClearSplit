#!/bin/bash
# Baseline verification script for S3 receipt upload

set -e

BASE_URL="http://127.0.0.1:8000"
SESSION_ID="a7611f19-8f6b-4107-a050-5bcd7b81af52"

echo "=== Baseline Verification ==="
echo ""

# 1. Test server health
echo "1. Testing server health..."
HEALTH=$(curl -s "$BASE_URL/health")
if [[ "$HEALTH" == *"ok"* ]]; then
    echo "✓ Server is running"
else
    echo "✗ Server health check failed: $HEALTH"
    exit 1
fi
echo ""

# 2. Get a fresh token (you'll need to replace with actual credentials)
echo "2. Testing receipt upload endpoint..."
echo "   Using existing session: $SESSION_ID"
echo ""

# Create test image if it doesn't exist
if [ ! -f "test-receipt.png" ]; then
    echo "Creating test image..."
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > test-receipt.png
fi

# Note: Replace TOKEN with actual token
TOKEN="REPLACE_WITH_ACTUAL_TOKEN"

echo "Curl command:"
echo "curl -X POST \"$BASE_URL/shopping-sessions/$SESSION_ID/receipt\" \\"
echo "  -H \"Authorization: Bearer [TOKEN]\" \\"
echo "  -F \"file=@test-receipt.png\""
echo ""

# Uncomment to actually run (after setting TOKEN):
# RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "$BASE_URL/shopping-sessions/$SESSION_ID/receipt" \
#   -H "Authorization: Bearer $TOKEN" \
#   -F "file=@test-receipt.png")
# 
# HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
# BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
# 
# echo "HTTP Status: $HTTP_CODE"
# echo "Response:"
# echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
# 
# if [ "$HTTP_CODE" = "201" ]; then
#     STORAGE_KEY=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin)['storage_key'])" 2>/dev/null)
#     echo ""
#     echo "✓ Upload successful"
#     echo "Storage key: $STORAGE_KEY"
# else
#     echo ""
#     echo "✗ Upload failed"
#     exit 1
# fi

echo ""
echo "3. Database verification:"
echo "   Run this SQL query to check storage_key:"
echo ""
echo "   SELECT id, session_id, storage_key, content_type, created_at"
echo "   FROM receipt_uploads"
echo "   WHERE session_id = '$SESSION_ID'"
echo "   ORDER BY created_at DESC"
echo "   LIMIT 1;"
echo ""
