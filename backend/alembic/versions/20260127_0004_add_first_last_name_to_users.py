"""add first_name and last_name to users

Revision ID: 20260127_0004
Revises: 20250110_0003
Create Date: 2026-01-27
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "20260127_0004"
down_revision = "20250110_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add first_name and last_name columns as nullable first (for existing users)
    op.add_column("users", sa.Column("first_name", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("last_name", sa.Text(), nullable=True))
    
    # For existing users, set a default value (you may want to update these manually)
    op.execute("UPDATE users SET first_name = 'User', last_name = '' WHERE first_name IS NULL")
    
    # Now make them NOT NULL
    op.alter_column("users", "first_name", nullable=False)
    op.alter_column("users", "last_name", nullable=False)


def downgrade() -> None:
    op.drop_column("users", "last_name")
    op.drop_column("users", "first_name")
