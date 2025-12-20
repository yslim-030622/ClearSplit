import os
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

settings = get_settings()

# Use NullPool for tests to avoid connection pool exhaustion
# In production, use default pooling with size/overflow limits
is_testing = os.getenv("PYTEST_CURRENT_TEST") is not None

if is_testing:
    # No connection pooling in tests - create/dispose connections as needed
    engine = create_async_engine(
        settings.database_url,
        future=True,
        poolclass=NullPool,
    )
else:
    # Production: use connection pooling
    engine = create_async_engine(
        settings.database_url,
        future=True,
        pool_size=5,
        max_overflow=10,
        pool_recycle=3600,
    )

SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncSession:
    async with SessionLocal() as session:
        yield session
