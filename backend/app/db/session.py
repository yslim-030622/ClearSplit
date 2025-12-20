"""Database session management."""

import os
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

settings = get_settings()

# Detect test environment
is_testing = os.getenv("PYTEST_CURRENT_TEST") is not None

if is_testing:
    # Test mode: NullPool + no pool_pre_ping to avoid event loop issues
    # Each SessionLocal() call gets a fresh connection
    engine = create_async_engine(
        settings.database_url,
        future=True,
        poolclass=NullPool,
        echo=False,  # Set to True for debugging
    )
else:
    # Production mode: standard connection pooling
    engine = create_async_engine(
        settings.database_url,
        future=True,
        pool_size=5,
        max_overflow=10,
        pool_recycle=3600,
        pool_pre_ping=True,
    )

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncSession:
    """Dependency for FastAPI routes."""
    async with SessionLocal() as session:
        yield session
