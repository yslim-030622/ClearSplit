"""Pytest configuration and fixtures for model tests.

These tests require a running Postgres database (via docker-compose).
The database should have migrations applied (alembic upgrade head).
"""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import SessionLocal


@pytest.fixture(scope="function")
async def session() -> AsyncSession:
    """Create a test database session.

    Note: This uses the existing database connection from app.db.session.
    Ensure migrations are applied before running tests.
    """
    async with SessionLocal() as session:
        # Start a transaction
        async with session.begin():
            yield session
            # Rollback after test
            await session.rollback()

