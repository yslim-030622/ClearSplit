#!/bin/bash
# Secret Scanner - Detects common secret patterns in code
# Run before committing to prevent accidental secret leaks

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Scanning for secrets in tracked files..."
echo ""

ISSUES_FOUND=0

# Patterns to search for (regex)
declare -a PATTERN_NAMES=(
    "Hardcoded JWT Secret"
    "Hardcoded Password"
    "Database URL with Password"
    "API Key"
    "AWS Access Key"
    "Private Key"
    "Generic Secret"
)

declare -a PATTERN_REGEXES=(
    'JWT_SECRET\s*=\s*["\047][^"\047]{10,}["\047]'
    '(password|passwd|pwd)\s*=\s*["\047][^"\047]{3,}["\047]'
    'postgresql://[^:]+:[^@]+@'
    'api[_-]?key\s*=\s*["\047][^"\047]{10,}["\047]'
    'AKIA[0-9A-Z]{16}'
    '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'
    '(secret|token)\s*=\s*["\047][a-zA-Z0-9]{20,}["\047]'
)

# Files to scan (only git-tracked files, excluding safe paths)
FILES=$(git ls-files | grep -v -E '(\.env\.example|SECURITY\.md|secret-scan\.sh|\.md$|\.txt$|\.gitignore|LICENSE|\.yml$)' || true)

if [ -z "$FILES" ]; then
    echo -e "${GREEN}✅ No files to scan${NC}"
    exit 0
fi

# Scan each pattern
for i in "${!PATTERN_NAMES[@]}"; do
    pattern_name="${PATTERN_NAMES[$i]}"
    pattern="${PATTERN_REGEXES[$i]}"
    
    # Use grep with extended regex
    MATCHES=$(echo "$FILES" | xargs grep -n -E -i "$pattern" 2>/dev/null || true)
    
    if [ -n "$MATCHES" ]; then
        echo -e "${RED}❌ Found: $pattern_name${NC}"
        echo "$MATCHES" | while IFS= read -r line; do
            echo -e "   ${YELLOW}$line${NC}"
        done
        echo ""
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
done

# Check for .env files that shouldn't be committed
BANNED_ENV_FILES=$(git ls-files | grep -E '\.env$|\.env\.local|\.env\.prod|\.env\.production' || true)
if [ -n "$BANNED_ENV_FILES" ]; then
    echo -e "${RED}❌ Found tracked .env files (should be gitignored):${NC}"
    echo "$BANNED_ENV_FILES" | while IFS= read -r file; do
        echo -e "   ${YELLOW}$file${NC}"
    done
    echo ""
    echo -e "${YELLOW}Remove with: git rm --cached <filename>${NC}"
    echo ""
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check for common test/dummy secrets that might be hardcoded
DUMMY_SECRETS=$(echo "$FILES" | xargs grep -n -E '(test-secret|changeme|your-secret-here|password123|admin123)' 2>/dev/null || true)
if [ -n "$DUMMY_SECRETS" ]; then
    echo -e "${YELLOW}⚠️  Warning: Found potential dummy/test secrets:${NC}"
    echo "$DUMMY_SECRETS" | while IFS= read -r line; do
        echo -e "   $line"
    done
    echo -e "${YELLOW}   → Ensure these are only in test files, not production code${NC}"
    echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ No secrets detected in tracked files${NC}"
    echo -e "${GREEN}✅ Safe to commit${NC}"
    exit 0
else
    echo -e "${RED}❌ Found $ISSUES_FOUND issue(s)${NC}"
    echo ""
    echo "🔒 Action Required:"
    echo "  1. Remove hardcoded secrets from code"
    echo "  2. Use .env.local (gitignored) for local secrets"
    echo "  3. Use environment variables or secret managers"
    echo "  4. If secret was committed, rotate it immediately"
    echo ""
    echo "📖 See SECURITY.md for details"
    exit 1
fi

