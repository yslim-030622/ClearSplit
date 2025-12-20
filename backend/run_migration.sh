#!/bin/bash
# Run migrations with explicit DATABASE_URL

set -e

cd "$(dirname "$0")"
source .venv/bin/activate

# Get DATABASE_URL from environment or use default
DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit}"

echo "Running migrations with DATABASE_URL: ${DATABASE_URL%%@*}@***"
export DATABASE_URL

alembic upgrade head

echo "✓ Migrations completed successfully"


