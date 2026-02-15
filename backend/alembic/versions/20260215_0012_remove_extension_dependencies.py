"""remove uuid-ossp/citext runtime dependency

Revision ID: 20260215_0012
Revises: 20260214_0011
Create Date: 2026-02-15
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "20260215_0012"
down_revision: Union[str, None] = "20260214_0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Migrate legacy CITEXT columns to TEXT when present.
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'users'
                  AND column_name = 'email'
                  AND udt_name = 'citext'
            ) THEN
                ALTER TABLE users
                ALTER COLUMN email TYPE TEXT
                USING email::text;
            END IF;
        END;
        $$;
        """
    )
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'users'
                  AND column_name = 'username'
                  AND udt_name = 'citext'
            ) THEN
                ALTER TABLE users
                ALTER COLUMN username TYPE TEXT
                USING username::text;
            END IF;
        END;
        $$;
        """
    )

    # Replace uuid-ossp defaults with built-in gen_random_uuid().
    op.execute(
        """
        DO $$
        DECLARE
            rec RECORD;
        BEGIN
            FOR rec IN
                SELECT table_name, column_name
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND column_default ILIKE '%uuid_generate_v4%'
            LOOP
                EXECUTE format(
                    'ALTER TABLE %I ALTER COLUMN %I SET DEFAULT gen_random_uuid()',
                    rec.table_name,
                    rec.column_name
                );
            END LOOP;
        END;
        $$;
        """
    )

    op.execute("DROP EXTENSION IF EXISTS citext;")
    op.execute('DROP EXTENSION IF EXISTS "uuid-ossp";')


def downgrade() -> None:
    op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";')
    op.execute("CREATE EXTENSION IF NOT EXISTS citext;")

    op.execute(
        """
        ALTER TABLE users
        ALTER COLUMN email TYPE CITEXT
        USING email::citext;
        """
    )
    op.execute(
        """
        ALTER TABLE users
        ALTER COLUMN username TYPE CITEXT
        USING username::citext;
        """
    )

    op.execute(
        """
        DO $$
        DECLARE
            rec RECORD;
        BEGIN
            FOR rec IN
                SELECT table_name, column_name
                FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND column_default ILIKE '%gen_random_uuid%'
            LOOP
                EXECUTE format(
                    'ALTER TABLE %I ALTER COLUMN %I SET DEFAULT uuid_generate_v4()',
                    rec.table_name,
                    rec.column_name
                );
            END LOOP;
        END;
        $$;
        """
    )
