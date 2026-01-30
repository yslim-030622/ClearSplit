"""add username to users

Revision ID: 20260128_0005
Revises: 20260127_0004
Create Date: 2026-01-28
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "20260128_0005"
down_revision = "20260127_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add username column as CITEXT (case-insensitive) with unique constraint
    # Since database is cleared, we can make it required from the start
    op.add_column(
        "users",
        sa.Column(
            "username",
            postgresql.CITEXT(),
            nullable=False,
            unique=True,
        ),
    )
    
    # Create index for username lookups
    op.create_index("idx_users_username", "users", ["username"])


def downgrade() -> None:
    op.drop_index("idx_users_username", table_name="users")
    op.drop_column("users", "username")
