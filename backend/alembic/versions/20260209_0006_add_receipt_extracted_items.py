"""add receipt extracted items table

Revision ID: 20260209_0006
Revises: 20260128_0005
Create Date: 2026-02-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '20260209_0006'
down_revision: Union[str, None] = '20260128_0005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create receipt_extracted_items table."""
    op.create_table(
        'receipt_extracted_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('receipt_upload_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('name', sa.Text(), nullable=False),
        sa.Column('quantity', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('unit_price_cents', sa.BigInteger(), nullable=True),
        sa.Column('total_cents', sa.BigInteger(), nullable=False),
        sa.Column('raw_line', sa.Text(), nullable=True),
        sa.Column('confidence', sa.Float(), nullable=True),
        sa.Column('created_at', postgresql.TIMESTAMP(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['receipt_upload_id'], ['receipt_uploads.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_receipt_extracted_items_receipt_upload_id'), 'receipt_extracted_items', ['receipt_upload_id'], unique=False)


def downgrade() -> None:
    """Drop receipt_extracted_items table."""
    op.drop_index(op.f('ix_receipt_extracted_items_receipt_upload_id'), table_name='receipt_extracted_items')
    op.drop_table('receipt_extracted_items')
