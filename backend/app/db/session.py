from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings
from app.db.connect_args import build_asyncpg_engine_config, normalize_env_name

settings = get_settings()
database_url = settings.get_database_url()
env_name = normalize_env_name(settings.env)
engine_url, connect_args = build_asyncpg_engine_config(
    database_url,
    env_name=env_name,
    connect_timeout_seconds=settings.db_connect_timeout_seconds,
)

engine = create_async_engine(
    engine_url,
    future=True,
    pool_pre_ping=True,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_timeout=settings.db_pool_timeout_seconds,
    pool_recycle=settings.db_pool_recycle_seconds,
    connect_args=connect_args,
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncSession:
    async with SessionLocal() as session:
        yield session
