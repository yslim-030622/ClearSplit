"""Pytest configuration and fixtures for model tests.

These tests require a running Postgres database (via docker-compose).
The database should have migrations applied (alembic upgrade head).
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import SessionLocal, get_session
from app.main import app


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


@pytest.fixture(scope="function")
async def client(session: AsyncSession) -> AsyncClient:
    """Create a test HTTP client."""
    async def override_get_session():
        yield session

    app.dependency_overrides[get_session] = override_get_session

    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()

