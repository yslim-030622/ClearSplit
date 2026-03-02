"""add async_jobs table with       
  partial unique index

Revision ID: 05c5a0294bab
Revises: 20260216_0014
Create Date: 2026-03-01 19:51:58.838527

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '05c5a0294bab'
down_revision: Union[str, None] = '20260216_0014'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('async_jobs',
    sa.Column('id', sa.UUID(), server_default=sa.text('gen_random_uuid()'), nullable=False),
    sa.Column('job_type', sa.String(length=50), nullable=False),
    sa.Column('status', sa.String(length=20), server_default='queued', nullable=False),
    sa.Column('attempt', sa.Integer(), server_default='0', nullable=False),
    sa.Column('max_attempts', sa.Integer(), server_default='3', nullable=False),
    sa.Column('receipt_upload_id', sa.UUID(), nullable=True),
    sa.Column('created_by_user_id', sa.UUID(), nullable=False),
    sa.Column('created_at', postgresql.TIMESTAMP(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('started_at', postgresql.TIMESTAMP(timezone=True), nullable=True),
    sa.Column('finished_at', postgresql.TIMESTAMP(timezone=True), nullable=True),
    sa.Column('last_error', sa.Text(), nullable=True),
    sa.Column('result_summary', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['receipt_upload_id'], ['receipt_uploads.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_async_jobs_active_receipt', 'async_jobs', ['job_type', 'receipt_upload_id'], unique=True, postgresql_where=sa.text("status IN ('queued', 'running')"))
    op.create_index('ix_async_jobs_created_by', 'async_jobs', ['created_by_user_id'], unique=False)
    op.create_index('ix_async_jobs_receipt_upload', 'async_jobs', ['receipt_upload_id'], unique=False)
    op.create_index('ix_async_jobs_status', 'async_jobs', ['status'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_async_jobs_status', table_name='async_jobs')
    op.drop_index('ix_async_jobs_receipt_upload', table_name='async_jobs')
    op.drop_index('ix_async_jobs_created_by', table_name='async_jobs')
    op.drop_index('ix_async_jobs_active_receipt', table_name='async_jobs', postgresql_where=sa.text("status IN ('queued', 'running')"))
    op.drop_table('async_jobs')
