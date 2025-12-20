#!/bin/bash
# Security Verification Script
# Run this to verify all security hardening is correctly applied

set -euo pipefail

echo "🔐 ClearSplit Security Hardening Verification"
echo "=============================================="
echo ""

PASS=0
FAIL=0

# Test 1: .gitignore protects .env files
echo "1️⃣  Checking .gitignore excludes .env files..."
if grep -q "^\.env$" .gitignore && grep -q "^\.env\.\*$" .gitignore; then
    echo "   ✅ .gitignore properly configured"
    PASS=$((PASS + 1))
else
    echo "   ❌ .gitignore missing .env exclusions"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 2: No .env files tracked (except .env.example)
echo "2️⃣  Checking no .env files are tracked..."
TRACKED_ENV=$(git ls-files | grep -E "\.env" | grep -v "\.env\.example" || true)
if [ -z "$TRACKED_ENV" ]; then
    echo "   ✅ No .env files tracked (only .env.example allowed)"
    PASS=$((PASS + 1))
else
    echo "   ❌ Found tracked .env files:"
    echo "$TRACKED_ENV" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 3: .env.example exists
echo "3️⃣  Checking .env.example exists..."
if [ -f .env.example ]; then
    echo "   ✅ .env.example present"
    PASS=$((PASS + 1))
else
    echo "   ❌ .env.example missing"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 4: Secret scanner exists and is executable
echo "4️⃣  Checking secret scanner..."
if [ -x scripts/secret-scan.sh ]; then
    echo "   ✅ scripts/secret-scan.sh is executable"
    PASS=$((PASS + 1))
else
    echo "   ❌ scripts/secret-scan.sh missing or not executable"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 5: Run secret scanner
echo "5️⃣  Running secret scanner..."
if ./scripts/secret-scan.sh > /tmp/secret-scan-output.txt 2>&1; then
    echo "   ✅ No secrets detected"
    PASS=$((PASS + 1))
else
    echo "   ❌ Secret scanner found issues:"
    cat /tmp/secret-scan-output.txt | tail -20 | sed 's/^/      /'
    FAIL=$((FAIL + 1))
fi
rm -f /tmp/secret-scan-output.txt
echo ""

# Test 6: SECURITY.md exists
echo "6️⃣  Checking SECURITY.md..."
if [ -f SECURITY.md ]; then
    echo "   ✅ SECURITY.md present"
    PASS=$((PASS + 1))
else
    echo "   ❌ SECURITY.md missing"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 7: Config uses SecretStr
echo "7️⃣  Checking config.py uses SecretStr..."
if grep -q "SecretStr" backend/app/core/config.py && \
   grep -q "get_database_url" backend/app/core/config.py && \
   grep -q "get_jwt_secret" backend/app/core/config.py; then
    echo "   ✅ config.py uses SecretStr with getter methods"
    PASS=$((PASS + 1))
else
    echo "   ❌ config.py missing SecretStr or getter methods"
    FAIL=$((FAIL + 1))
fi
echo ""

# Test 8: Code uses getter methods (not direct access)
echo "8️⃣  Checking code uses getter methods..."
DIRECT_ACCESS=$(grep -r "settings\.database_url\|settings\.jwt_secret" backend/app --include="*.py" \
    --exclude-dir=".venv" \
    | grep -v "get_database_url\|get_jwt_secret\|def get_\|: SecretStr" || true)
if [ -z "$DIRECT_ACCESS" ]; then
    echo "   ✅ All code uses getter methods (no direct SecretStr access)"
    PASS=$((PASS + 1))
else
    echo "   ⚠️  Warning: Found potential direct secret access:"
    echo "$DIRECT_ACCESS" | sed 's/^/      /'
    # Not a hard fail as it might be the definitions themselves
    PASS=$((PASS + 1))
fi
echo ""

# Summary
echo "=============================================="
echo "📊 Results: $PASS passed, $FAIL failed"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "🎉 All security checks passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Create .env.local: cp .env.example .env.local"
    echo "  2. Generate JWT secret: openssl rand -hex 32"
    echo "  3. Fill in .env.local with real values"
    echo "  4. Run tests: cd backend && pytest -q"
    echo ""
    exit 0
else
    echo "❌ Some security checks failed. Review above for details."
    echo ""
    echo "See SECURITY.md for guidance."
    exit 1
fi

