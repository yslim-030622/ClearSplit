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
from app.models.user import User
from app.auth.password import hash_password


# Create a test engine with NullPool to avoid connection issues
test_engine = create_async_engine(
    get_settings().database_url,
    echo=False,
    poolclass=NullPool,
)

class TestSession(AsyncSession):
    """Test session that converts commits to flushes for test isolation."""
    
    async def commit(self):
        """Override commit to flush instead, keeping changes in transaction."""
        await self.flush()


TestSessionLocal = async_sessionmaker(
    test_engine,
    class_=TestSession,
    expire_on_commit=False,
)


@pytest_asyncio.fixture(scope="function")
async def session() -> AsyncSession:
    """Create a test database session with proper transaction rollback.
    
    Each test gets a completely isolated transaction that's rolled back at the end.
    This ensures no data persists between tests.
    """
    # Get a fresh connection for each test
    connection = await test_engine.connect()
    # Start a transaction on the connection - this isolates all changes
    transaction = await connection.begin()
    
    # Create test session bound to the connection
    # TestSession overrides commit() to flush() automatically
    session = TestSession(bind=connection, expire_on_commit=False)
    
    try:
        yield session
    finally:
        # CRITICAL: Always rollback to clean up - this is essential for test isolation
        # Rollback the connection transaction (undoes all changes)
        try:
            if transaction.is_active:
                await transaction.rollback()
        except Exception:
            # If rollback fails, try to close connection which will also rollback
            pass
        # Close session and connection
        try:
            await session.close()
        except Exception:
            pass
        try:
            await connection.close()
        except Exception:
            pass


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


# ============================================================================
# Test Helper Functions
# ============================================================================

def create_test_user(
    email: str,
    password: str = "password123",
    username: str | None = None,
    first_name: str = "Test",
    last_name: str = "User",
) -> User:
    """Create a test user with all required fields.
    
    Args:
        email: User email (required)
        password: User password (default: "password123")
        username: Username (default: derived from email)
        first_name: First name (default: "Test")
        last_name: Last name (default: "User")
    
    Returns:
        User instance with all required fields
    """
    if username is None:
        # Generate username from email
        username = email.split("@")[0]
    
    return User(
        username=username,
        email=email,
        password_hash=hash_password(password),
        first_name=first_name,
        last_name=last_name,
    )

