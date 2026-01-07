"""add shopping tables

Revision ID: 20250107_0002
Revises: 20241218_0001
Create Date: 2025-01-07
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "20250107_0002"
down_revision = "20241218_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create shopping_sessions table
    op.create_table(
        "shopping_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("shopping_date", sa.Date()),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default=sa.text("'USD'")),
        sa.Column("paid_by_membership_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
    )

    # Create shopping_session_participants table
    op.create_table(
        "shopping_session_participants",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("membership_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("session_id", "membership_id", name="uq_session_participants"),
        sa.ForeignKeyConstraint(["session_id"], ["shopping_sessions.id"], ondelete="CASCADE"),
    )

    # Create receipt_uploads table
    op.create_table(
        "receipt_uploads",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("storage_key", sa.Text(), nullable=False),
        sa.Column("content_type", sa.String(length=100), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["session_id"], ["shopping_sessions.id"], ondelete="CASCADE"),
    )

    # Create shopping_items table
    op.create_table(
        "shopping_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("unit_price_cents", sa.BigInteger()),
        sa.Column("total_cents", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("quantity >= 1", name="chk_shopping_items_quantity_positive"),
        sa.CheckConstraint("unit_price_cents IS NULL OR unit_price_cents >= 0", name="chk_shopping_items_unit_price_nonnegative"),
        sa.CheckConstraint("total_cents > 0", name="chk_shopping_items_total_positive"),
        sa.ForeignKeyConstraint(["session_id"], ["shopping_sessions.id"], ondelete="CASCADE"),
    )

    # Create shopping_item_splits table
    op.create_table(
        "shopping_item_splits",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("item_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("membership_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("share_cents", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("item_id", "membership_id", name="uq_item_splits"),
        sa.CheckConstraint("share_cents >= 0", name="chk_shopping_item_splits_share_nonnegative"),
        sa.ForeignKeyConstraint(["item_id"], ["shopping_items.id"], ondelete="CASCADE"),
    )


def downgrade() -> None:
    op.drop_table("shopping_item_splits")
    op.drop_table("shopping_items")
    op.drop_table("receipt_uploads")
    op.drop_table("shopping_session_participants")
    op.drop_table("shopping_sessions")

