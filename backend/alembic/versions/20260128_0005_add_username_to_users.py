"""add username to users

Revision ID: 20260128_0005
Revises: 20260127_0004
Create Date: 2026-01-28
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "20260128_0005"
down_revision = "20260127_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add username as nullable first so existing rows can be backfilled safely.
    op.add_column("users", sa.Column("username", sa.Text(), nullable=True))

    op.execute(
        """
        WITH ranked AS (
            SELECT
                id,
                COALESCE(NULLIF(split_part(email::text, '@', 1), ''), 'user') AS base_name,
                row_number() OVER (
                    PARTITION BY lower(COALESCE(NULLIF(split_part(email::text, '@', 1), ''), 'user'))
                    ORDER BY created_at, id
                ) AS rn
            FROM users
        )
        UPDATE users u
        SET username = CASE
            WHEN r.rn = 1 THEN r.base_name
            ELSE r.base_name || '_' || r.rn
        END
        FROM ranked r
        WHERE u.id = r.id AND u.username IS NULL;
        """
    )

    op.alter_column("users", "username", nullable=False)
    op.create_unique_constraint("uq_users_username", "users", ["username"])
    op.create_index("idx_users_username", "users", ["username"])


def downgrade() -> None:
    op.drop_index("idx_users_username", table_name="users")
    op.drop_constraint("uq_users_username", "users", type_="unique")
    op.drop_column("users", "username")
