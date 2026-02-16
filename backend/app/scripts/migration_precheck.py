import asyncio
import os
import sys
from pathlib import Path

import asyncpg

# Allow `python app/scripts/migration_precheck.py` in job runners where module mode is inconvenient.
if __package__ in {None, ""}:
    sys.path.append(str(Path(__file__).resolve().parents[2]))

from app.db.connect_args import build_asyncpg_engine_config, normalize_env_name

EMAIL_DUP_SQL = """
SELECT COUNT(*)::int
FROM (
    SELECT lower(email)
    FROM users
    GROUP BY lower(email)
    HAVING COUNT(*) > 1
) duplicates;
"""

USERNAME_DUP_SQL = """
SELECT COUNT(*)::int
FROM (
    SELECT lower(username)
    FROM users
    GROUP BY lower(username)
    HAVING COUNT(*) > 1
) duplicates;
"""


async def main() -> None:
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is not configured in migration job env")

    # SQLAlchemy accepts both `postgresql://` and `postgresql+asyncpg://`, but `postgres://`
    # is a common variant that can appear in hosted providers.
    if database_url.startswith("postgres://"):
        database_url = "postgresql://" + database_url.split("://", 1)[1]

    env_name = normalize_env_name(os.getenv("ENV"))
    connect_timeout_raw = os.getenv("DB_CONNECT_TIMEOUT_SECONDS")
    try:
        connect_timeout_seconds = float(connect_timeout_raw) if connect_timeout_raw else 10.0
    except ValueError:
        connect_timeout_seconds = 10.0

    sqlalchemy_url, connect_args = build_asyncpg_engine_config(
        database_url,
        env_name=env_name,
        connect_timeout_seconds=connect_timeout_seconds,
    )

    # build_asyncpg_engine_config returns a SQLAlchemy URL. asyncpg accepts plain postgresql://.
    dsn = sqlalchemy_url
    if dsn.startswith("postgresql+asyncpg://"):
        dsn = "postgresql://" + dsn.split("://", 1)[1]

    conn = await asyncpg.connect(dsn, **connect_args)
    try:
        users_exists = await conn.fetchval("SELECT to_regclass('public.users') IS NOT NULL;")
        if not users_exists:
            print("users table not found; skipping duplicate precheck")
            return

        duplicate_emails = await conn.fetchval(EMAIL_DUP_SQL)
        duplicate_usernames = await conn.fetchval(USERNAME_DUP_SQL)
    finally:
        await conn.close()

    if duplicate_emails or duplicate_usernames:
        raise SystemExit(
            "Duplicate normalized identities detected before migration "
            f"(email={duplicate_emails}, username={duplicate_usernames})."
        )

    print("Duplicate identity precheck passed")


if __name__ == "__main__":
    asyncio.run(main())
