"""Pytest configuration and fixtures for model tests.

These tests require a running Postgres database (via docker-compose).
The database should have migrations applied (alembic upgrade head).
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.db.session import SessionLocal, get_session
from app.main import app


@pytest.fixture(scope="function", autouse=True)
async def cleanup_database():
    """Clean up database before each test.
    
    This fixture runs automatically before each test to ensure a clean state.
    Uses longer delays to ensure all async operations complete before next test.
    """
    import asyncio
    # Wait for previous test's connections to fully close
    await asyncio.sleep(0.2)
    
    async with SessionLocal() as session:
        try:
            # Use a single command to truncate all tables
            await session.execute(text("""
                TRUNCATE TABLE 
                    expense_splits,
                    expenses,
                    settlements,
                    settlement_batches,
                    activity_log,
                    idempotency_keys,
                    memberships,
                    groups,
                    users
                RESTART IDENTITY CASCADE
            """))
            await session.commit()
        except Exception:
            await session.rollback()
        finally:
            await session.close()
    
    yield
    
    # Allow connections to close after test
    await asyncio.sleep(0.2)


@pytest.fixture(scope="function")
async def session() -> AsyncSession:
    """Create a test database session for direct database operations.
    
    This session is separate from the HTTP client's session to avoid
    concurrent operation conflicts.
    """
    async with SessionLocal() as session:
        yield session


@pytest.fixture(scope="function")
async def client() -> AsyncClient:
    """Create a test HTTP client.
    
    The client gets its own session for each request to avoid
    asyncpg connection conflicts. Test isolation relies on
    database cleanup between tests (handled by cleanup_database fixture).
    """
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

    # Clear any overrides after test
    app.dependency_overrides.clear()

