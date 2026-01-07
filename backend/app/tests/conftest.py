"""Pytest configuration and fixtures for model tests.

These tests require a running Postgres database (via docker-compose).
The database should have migrations applied (alembic upgrade head).
"""

import asyncio
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.core.config import get_settings
from app.db.session import get_session
from app.main import app


# Create a test engine with NullPool to avoid connection issues
test_engine = create_async_engine(
    get_settings().database_url,
    echo=False,
    poolclass=NullPool,
)

TestSessionLocal = async_sessionmaker(
    test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


@pytest_asyncio.fixture(scope="function")
async def session() -> AsyncSession:
    """Create a test database session with proper transaction rollback.
    
    Each test gets a fresh transaction that is rolled back after the test completes.
    """
    connection = await test_engine.connect()
    transaction = await connection.begin()
    
    session = AsyncSession(bind=connection, expire_on_commit=False)
    
    try:
        yield session
    finally:
        await session.close()
        await transaction.rollback()
        await connection.close()


@pytest_asyncio.fixture(scope="function")
async def client(session: AsyncSession) -> AsyncClient:
    """Create a test HTTP client with session override."""
    async def override_get_session():
        yield session

    app.dependency_overrides[get_session] = override_get_session

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac

    app.dependency_overrides.clear()

