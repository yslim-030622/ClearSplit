#!/bin/bash
# Script to reproduce CI environment locally
# This runs the exact same commands as GitHub Actions CI

set -e  # Exit on error

echo "🔧 Reproducing CI environment locally..."
echo ""

# Check if we're in the backend directory
if [ ! -f "requirements.txt" ]; then
    echo "❌ Error: Run this script from the backend/ directory"
    exit 1
fi

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo "📦 Creating virtual environment..."
    python3.12 -m venv .venv
fi

# Activate virtual environment
echo "🔌 Activating virtual environment..."
source .venv/bin/activate

# Install/update dependencies
echo "📥 Installing dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt -q

# Check PostgreSQL is running
echo "🐘 Checking PostgreSQL..."
if ! docker-compose ps | grep -q "postgres.*Up"; then
    echo "⚠️  PostgreSQL not running. Starting..."
    docker-compose up -d
    echo "⏳ Waiting for PostgreSQL to be ready..."
    sleep 3
fi

# Create test .env (matching CI)
echo "📝 Creating CI-matching .env..."
cat > .env << EOF
ENV=test
DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit
JWT_SECRET=test-secret-key-for-ci-only-not-for-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
EOF

# Run migrations (same as CI)
echo "🗄️  Running database migrations..."
alembic upgrade head

# Run tests (same as CI)
echo ""
echo "🧪 Running tests (same command as CI)..."
echo "   Command: pytest -q --tb=short"
echo ""

pytest -q --tb=short

# Check result
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SUCCESS! All tests passed (same as CI will)"
    echo ""
    echo "Your code is ready to push. CI will pass. 🚀"
else
    echo ""
    echo "❌ FAILURE! Tests failed"
    echo ""
    echo "Fix these failures before pushing - CI will fail too."
    exit 1
fi

