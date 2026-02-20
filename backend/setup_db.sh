#!/bin/bash
# Setup database and run migrations for local Docker Compose workflow.

set -euo pipefail

echo "Setting up database..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

POSTGRES_USER=${POSTGRES_USER:-clearsplit}
POSTGRES_DB=${POSTGRES_DB:-clearsplit}

echo "Starting database container..."
compose up -d db

echo "Waiting for database to be ready..."
DB_READY="no"
for _ in {1..30}; do
    if compose exec -T db pg_isready -U "$POSTGRES_USER" -d postgres >/dev/null 2>&1; then
        DB_READY="yes"
        break
    fi
    sleep 2
done

if [ "$DB_READY" != "yes" ]; then
    echo "Database did not become ready in time."
    exit 1
fi

echo "Checking database setup..."
DB_EXISTS="$(
    compose exec -T db \
        psql -U "$POSTGRES_USER" --set=target_db="$POSTGRES_DB" -tAc \
        "SELECT 1 FROM pg_database WHERE datname = :'target_db'" | tr -d '[:space:]'
)"

if [ "$DB_EXISTS" = "1" ]; then
    echo "Database '$POSTGRES_DB' already exists"
    echo "User '$POSTGRES_USER' already exists"
else
    echo "Database does not exist. Creating..."
    compose exec -T db psql -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 -c \
        "CREATE DATABASE \"$POSTGRES_DB\";"
    echo "Database created"
fi

echo "Running migrations..."
cd "$SCRIPT_DIR"

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

alembic upgrade head

echo "Database setup complete."
