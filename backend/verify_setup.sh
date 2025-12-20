#!/bin/bash
# Verify backend setup before testing

set -e

echo "=== Verifying Backend Setup ==="
echo ""

# Check database container
echo "1. Checking database container..."
if docker-compose ps | grep -q "clearsplit-db-1.*healthy"; then
    echo "✓ Database container is running and healthy"
else
    echo "✗ Database container is not running or not healthy"
    echo "  Run: docker-compose up -d db"
    exit 1
fi
echo ""

# Check database connection
echo "2. Testing database connection..."
if docker exec clearsplit-db-1 psql -U clearsplit -d clearsplit -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Database connection successful"
else
    echo "✗ Database connection failed"
    exit 1
fi
echo ""

# Check if users table exists
echo "3. Checking database tables..."
TABLE_EXISTS=$(docker exec clearsplit-db-1 psql -U clearsplit -d clearsplit -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users');" 2>/dev/null || echo "f")

if [ "$TABLE_EXISTS" = "t" ]; then
    echo "✓ Users table exists (migrations have run)"
else
    echo "✗ Users table does not exist"
    echo "  Run: cd backend && source .venv/bin/activate && alembic upgrade head"
    exit 1
fi
echo ""

# Check server is running
echo "4. Checking server..."
if curl -s --max-time 2 http://localhost:8000/health > /dev/null 2>&1; then
    echo "✓ Server is running and responding"
else
    echo "✗ Server is not responding"
    echo "  Run: cd backend && make run"
    exit 1
fi
echo ""

echo "=== All checks passed! Ready for API testing ==="


