import asyncio
import os

import asyncpg

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
    dsn = os.getenv("DATABASE_URL", "").strip()
    if not dsn:
        raise SystemExit("DATABASE_URL is not configured in migration job env")

    # The app uses SQLAlchemy async URLs; asyncpg expects a plain postgresql:// URL.
    if dsn.startswith("postgresql+asyncpg://"):
        dsn = "postgresql://" + dsn.split("://", 1)[1]

    if not dsn.startswith(("postgresql://", "postgres://")):
        raise SystemExit(
            "DATABASE_URL must use postgresql:// or postgresql+asyncpg:// for migration precheck"
        )

    conn = await asyncpg.connect(dsn)
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

