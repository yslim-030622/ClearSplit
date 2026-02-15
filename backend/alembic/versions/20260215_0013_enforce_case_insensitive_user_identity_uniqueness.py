"""enforce case-insensitive uniqueness for user email/username

Revision ID: 20260215_0013
Revises: 20260215_0012
Create Date: 2026-02-15
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


# revision identifiers, used by Alembic.
revision: str = "20260215_0013"
down_revision: Union[str, None] = "20260215_0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _count_case_insensitive_duplicates(column_name: str) -> int:
    bind = op.get_bind()
    result = bind.execute(
        sa.text(
            f"""
            SELECT COUNT(*)
            FROM (
                SELECT lower({column_name}) AS normalized_value
                FROM users
                GROUP BY lower({column_name})
                HAVING COUNT(*) > 1
            ) duplicates
            """
        )
    )
    return int(result.scalar_one())


def upgrade() -> None:
    duplicate_emails = _count_case_insensitive_duplicates("email")
    if duplicate_emails:
        raise RuntimeError(
            "Cannot enforce case-insensitive uniqueness for users.email "
            f"because {duplicate_emails} duplicate normalized value(s) exist. "
            "Deduplicate legacy users first."
        )

    duplicate_usernames = _count_case_insensitive_duplicates("username")
    if duplicate_usernames:
        raise RuntimeError(
            "Cannot enforce case-insensitive uniqueness for users.username "
            f"because {duplicate_usernames} duplicate normalized value(s) exist. "
            "Deduplicate legacy users first."
        )

    op.execute(
        """
        UPDATE users
        SET
            email = lower(email),
            username = lower(username)
        WHERE
            email <> lower(email)
            OR username <> lower(username);
        """
    )

    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_ci
        ON users ((lower(email)));
        """
    )
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_users_username_ci
        ON users ((lower(username)));
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_users_username_ci;")
    op.execute("DROP INDEX IF EXISTS uq_users_email_ci;")
