"""Pytest configuration and fixtures for model tests.

Test Strategy:
- Each test gets a fresh session (NullPool ensures no connection reuse)
- Cleanup runs on a dedicated, immediately-closed connection
- HTTP client and test code share the SAME session to prevent concurrent ops
- Delays ensure cleanup completes before next test starts
"""

import asyncio
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.db.session import engine, SessionLocal, get_session
from app.main import app


@pytest.fixture(scope="session")
def event_loop():
    """Create a session-scoped event loop.
    
    This ensures all async fixtures and tests share the same event loop,
    preventing "Future attached to a different loop" errors.
    """
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="function", autouse=True)
async def cleanup_database():
    """Clean database before and after each test.
    
    Uses engine.begin() to get a dedicated connection that auto-commits
    and closes immediately, avoiding interference with test sessions.
    """
    # Pre-test cleanup
    async with engine.begin() as conn:
        await conn.execute(text("""
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
        # Connection auto-commits and closes on context exit
    
    # Small delay to ensure cleanup connection fully closes
    await asyncio.sleep(0.05)
    
    yield
    
    # Post-test delay to ensure test connections close before next cleanup
    await asyncio.sleep(0.05)


@pytest.fixture(scope="function")
async def session() -> AsyncSession:
    """Create a test session for direct database operations.
    
    Important: If the test uses the `client` fixture, that client will
    SHARE this session. Do not use this session concurrently with HTTP
    requests in the same test.
    """
    async with SessionLocal() as session:
        yield session
        # Ensure rollback of any uncommitted changes
        await session.rollback()
        await session.close()


@pytest.fixture(scope="function")
async def client(session: AsyncSession) -> AsyncClient:
    """Create a test HTTP client.
    
    CRITICAL: This client shares the test's session to ensure only ONE
    connection is active at a time. This prevents asyncpg "operation in
    progress" errors.
    
    This means:
    - All HTTP requests in a test use the same DB connection as direct queries
    - You CANNOT make concurrent HTTP requests in a single test
    - You CAN make sequential requests without issues
    """
    # Override the app's get_session to use our test session
    async def override_get_session():
        yield session
    
    app.dependency_overrides[get_session] = override_get_session
    
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()

