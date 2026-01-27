"""add total_amount to shopping_sessions

Revision ID: 20250110_0003
Revises: 20250107_0002
Create Date: 2026-01-10 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250110_0003'
down_revision = '20250107_0002'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add total_amount column to shopping_sessions
    op.add_column(
        'shopping_sessions',
        sa.Column(
            'total_amount',
            sa.Numeric(precision=10, scale=2),
            nullable=True,
            comment='Optional total amount for quick splits without itemization'
        )
    )


def downgrade() -> None:
    # Remove total_amount column from shopping_sessions
    op.drop_column('shopping_sessions', 'total_amount')
