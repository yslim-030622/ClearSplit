#!/bin/bash
# Fix DATABASE_URL and run migrations

set -e

cd "$(dirname "$0")"
source .venv/bin/activate

echo "=== Fixing Database Connection ==="
echo ""

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Creating .env file..."
    cat > .env <<EOF
# Database
DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit

# JWT
JWT_SECRET=$(python -c "import secrets; print(secrets.token_urlsafe(32))")
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30

# Environment
ENV=local
EOF
    echo "✓ Created .env file"
else
    echo "✓ .env file exists"
    
    # Check if DATABASE_URL is correct
    if grep -q "postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit" .env; then
        echo "✓ DATABASE_URL is correct"
    else
        echo "⚠ DATABASE_URL may be incorrect"
        echo "  Expected: postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit"
        echo ""
        echo "Updating DATABASE_URL..."
        
        # Backup original
        cp .env .env.backup
        
        # Update DATABASE_URL if it exists, or add it
        if grep -q "^DATABASE_URL=" .env; then
            # Replace existing
            sed -i.bak 's|^DATABASE_URL=.*|DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit|' .env
        else
            # Add new
            echo "DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit" >> .env
        fi
        
        echo "✓ Updated DATABASE_URL"
        echo "  Backup saved to .env.backup"
    fi
fi

echo ""
echo "=== Running Migrations ==="
echo ""

# Export DATABASE_URL to ensure it's used
export DATABASE_URL="postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit"

# Run migrations
alembic upgrade head

echo ""
echo "=== Verifying Tables ==="
echo ""

# Check if tables were created
TABLE_COUNT=$(docker exec clearsplit-db-1 psql -U clearsplit -d clearsplit -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")

if [ "$TABLE_COUNT" -gt 0 ]; then
    echo "✓ Found $TABLE_COUNT tables"
    echo ""
    echo "Tables:"
    docker exec clearsplit-db-1 psql -U clearsplit -d clearsplit -c "\dt" 2>/dev/null | grep -E "^\s+public" || true
else
    echo "✗ No tables found"
    exit 1
fi

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "You can now:"
echo "  1. Start the server: make run"
echo "  2. Test the API: ./test_api.sh"


