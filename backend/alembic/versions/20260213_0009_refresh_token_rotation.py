"""add refresh token table for rotation and replay protection

Revision ID: 20260213_0009
Revises: 20260213_0008
Create Date: 2026-02-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "20260213_0009"
down_revision: Union[str, None] = "20260213_0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "refresh_tokens",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("uuid_generate_v4()"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("token_jti", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("replaced_by_jti", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("token_jti", name="uq_refresh_tokens_token_jti"),
    )
    op.create_index(
        "idx_refresh_tokens_user_expires",
        "refresh_tokens",
        ["user_id", "expires_at"],
        unique=False,
    )
    op.create_index(
        "idx_refresh_tokens_user_revoked",
        "refresh_tokens",
        ["user_id", "revoked_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_refresh_tokens_user_revoked", table_name="refresh_tokens")
    op.drop_index("idx_refresh_tokens_user_expires", table_name="refresh_tokens")
    op.drop_table("refresh_tokens")
