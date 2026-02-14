"""add friendships table for friends feature

Revision ID: 20260214_0011
Revises: 20260213_0010
Create Date: 2026-02-14
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "20260214_0011"
down_revision: Union[str, None] = "20260213_0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


friendship_status = postgresql.ENUM(
    "pending",
    "accepted",
    "declined",
    name="friendship_status",
)

friendship_status_ref = postgresql.ENUM(
    "pending",
    "accepted",
    "declined",
    name="friendship_status",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    friendship_status.create(bind, checkfirst=True)

    op.create_table(
        "friendships",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("uuid_generate_v4()"),
            nullable=False,
        ),
        sa.Column("user_low_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_high_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("requested_by_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "status",
            friendship_status_ref,
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_low_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_high_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["requested_by_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_low_id", "user_high_id", name="uq_friendships_user_pair"),
        sa.CheckConstraint("user_low_id <> user_high_id", name="chk_friendships_distinct_users"),
        sa.CheckConstraint(
            "requested_by_user_id = user_low_id OR requested_by_user_id = user_high_id",
            name="chk_friendships_requested_by_participant",
        ),
    )

    op.create_index(
        "idx_friendships_status_user_low",
        "friendships",
        ["status", "user_low_id"],
        unique=False,
    )
    op.create_index(
        "idx_friendships_status_user_high",
        "friendships",
        ["status", "user_high_id"],
        unique=False,
    )

    op.execute(
        """
        CREATE TRIGGER friendships_set_updated_at
        BEFORE UPDATE ON friendships
        FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS friendships_set_updated_at ON friendships;")
    op.drop_index("idx_friendships_status_user_high", table_name="friendships")
    op.drop_index("idx_friendships_status_user_low", table_name="friendships")
    op.drop_table("friendships")

    bind = op.get_bind()
    friendship_status.drop(bind, checkfirst=True)
