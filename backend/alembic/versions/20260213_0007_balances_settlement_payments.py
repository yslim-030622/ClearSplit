"""balances and settlement payment persistence

Revision ID: 20260213_0007
Revises: 20260209_0006
Create Date: 2026-02-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "20260213_0007"
down_revision: Union[str, None] = "20260209_0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


shopping_session_status = postgresql.ENUM(
    "active",
    "finalized",
    "settled",
    name="shopping_session_status",
)

settlement_payment_status = postgresql.ENUM(
    "pending",
    "confirmed",
    "voided",
    name="settlement_payment_status",
)

shopping_session_status_ref = postgresql.ENUM(
    "active",
    "finalized",
    "settled",
    name="shopping_session_status",
    create_type=False,
)

settlement_payment_status_ref = postgresql.ENUM(
    "pending",
    "confirmed",
    "voided",
    name="settlement_payment_status",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    shopping_session_status.create(bind, checkfirst=True)
    settlement_payment_status.create(bind, checkfirst=True)

    op.add_column(
        "shopping_sessions",
        sa.Column(
            "status",
            shopping_session_status_ref,
            nullable=False,
            server_default=sa.text("'active'"),
        ),
    )
    op.add_column(
        "shopping_sessions",
        sa.Column("finalized_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.add_column(
        "shopping_sessions",
        sa.Column("settled_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.create_unique_constraint(
        "uq_shopping_sessions_group_id",
        "shopping_sessions",
        ["id", "group_id"],
    )
    op.create_index(
        "idx_shopping_sessions_group_status_created",
        "shopping_sessions",
        ["group_id", "status", "created_at"],
        unique=False,
    )

    op.add_column(
        "shopping_items",
        sa.Column(
            "created_by_membership_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    op.execute(
        """
        UPDATE shopping_items AS si
        SET created_by_membership_id = ss.paid_by_membership_id
        FROM shopping_sessions AS ss
        WHERE si.session_id = ss.id
          AND si.created_by_membership_id IS NULL
        """
    )
    op.alter_column(
        "shopping_items",
        "created_by_membership_id",
        nullable=False,
    )
    op.create_foreign_key(
        "fk_shopping_items_created_by_membership",
        "shopping_items",
        "memberships",
        ["created_by_membership_id"],
        ["id"],
        ondelete="RESTRICT",
    )
    op.create_index(
        "idx_shopping_items_created_by",
        "shopping_items",
        ["created_by_membership_id"],
        unique=False,
    )

    op.create_table(
        "settlement_payments",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("from_membership", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("to_membership", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column(
            "status",
            settlement_payment_status_ref,
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("sent_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("confirmed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("id", "group_id", name="uq_settlement_payments_group_id"),
        sa.CheckConstraint(
            "amount_cents > 0",
            name="chk_settlement_payments_amount_positive",
        ),
        sa.CheckConstraint(
            "from_membership <> to_membership",
            name="chk_settlement_payments_from_to_diff",
        ),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["group_id", "from_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
        sa.ForeignKeyConstraint(
            ["group_id", "to_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
    )
    op.create_index(
        "idx_settlement_payments_group_created",
        "settlement_payments",
        ["group_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_settlement_payments_group_status",
        "settlement_payments",
        ["group_id", "status", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_settlement_payments_from_to",
        "settlement_payments",
        ["group_id", "from_membership", "to_membership"],
        unique=False,
    )

    op.create_table(
        "settlement_payment_sessions",
        sa.Column("payment_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.PrimaryKeyConstraint(
            "payment_id",
            "session_id",
            name="pk_settlement_payment_sessions",
        ),
        sa.ForeignKeyConstraint(
            ["payment_id"],
            ["settlement_payments.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["shopping_sessions.id"],
            ondelete="CASCADE",
        ),
    )
    op.create_index(
        "idx_settlement_payment_sessions_session",
        "settlement_payment_sessions",
        ["session_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "idx_settlement_payment_sessions_session",
        table_name="settlement_payment_sessions",
    )
    op.drop_table("settlement_payment_sessions")

    op.drop_index("idx_settlement_payments_from_to", table_name="settlement_payments")
    op.drop_index(
        "idx_settlement_payments_group_status",
        table_name="settlement_payments",
    )
    op.drop_index(
        "idx_settlement_payments_group_created",
        table_name="settlement_payments",
    )
    op.drop_table("settlement_payments")

    op.drop_index("idx_shopping_items_created_by", table_name="shopping_items")
    op.drop_constraint(
        "fk_shopping_items_created_by_membership",
        "shopping_items",
        type_="foreignkey",
    )
    op.drop_column("shopping_items", "created_by_membership_id")

    op.drop_index(
        "idx_shopping_sessions_group_status_created",
        table_name="shopping_sessions",
    )
    op.drop_constraint(
        "uq_shopping_sessions_group_id",
        "shopping_sessions",
        type_="unique",
    )
    op.drop_column("shopping_sessions", "settled_at")
    op.drop_column("shopping_sessions", "finalized_at")
    op.drop_column("shopping_sessions", "status")

    bind = op.get_bind()
    settlement_payment_status.drop(bind, checkfirst=True)
    shopping_session_status.drop(bind, checkfirst=True)
