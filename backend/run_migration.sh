#!/bin/bash
# Run migrations with explicit DATABASE_URL

set -euo pipefail

cd "$(dirname "$0")"

if [ -f "venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source venv/bin/activate
elif [ -f ".venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
else
    echo "No virtual environment found. Expected venv/ or .venv/ in backend/."
    exit 1
fi

# Get DATABASE_URL from environment or use default
DATABASE_URL="${DATABASE_URL:-postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit}"

echo "Running migrations with DATABASE_URL: ${DATABASE_URL%%@*}@***"
export DATABASE_URL

alembic upgrade head

echo "✓ Migrations completed successfully"

