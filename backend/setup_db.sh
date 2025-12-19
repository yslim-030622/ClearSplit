#!/bin/bash
# Setup database user and run migrations

set -e

echo "Setting up database..."

# Check if database container is running
if ! docker-compose ps | grep -q "clearsplit-db-1.*healthy"; then
    echo "Starting database container..."
    docker-compose up -d db
    echo "Waiting for database to be ready..."
    sleep 15
fi

echo "Checking database setup..."

# Get POSTGRES_USER from environment or use default
POSTGRES_USER=${POSTGRES_USER:-clearsplit}
POSTGRES_DB=${POSTGRES_DB:-clearsplit}

# Check if database exists
DB_EXISTS=$(docker exec clearsplit-db-1 psql -U "$POSTGRES_USER" -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$POSTGRES_DB" && echo "yes" || echo "no")

if [ "$DB_EXISTS" = "yes" ]; then
    echo "✓ Database '$POSTGRES_DB' already exists"
    echo "✓ User '$POSTGRES_USER' already exists"
else
    echo "Database does not exist. Creating..."
    docker exec -i clearsplit-db-1 psql -U "$POSTGRES_USER" <<EOF
CREATE DATABASE $POSTGRES_DB;
\q
EOF
    echo "✓ Database created"
fi

echo "Running migrations..."
cd "$(dirname "$0")"
source .venv/bin/activate
alembic upgrade head

echo "✓ Database setup complete!"

