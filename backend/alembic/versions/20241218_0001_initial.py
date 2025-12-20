"""initial schema

Revision ID: 20241218_0001
Revises:
Create Date: 2025-01-04
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = "20241218_0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";')
    op.execute('CREATE EXTENSION IF NOT EXISTS citext;')

    # Explicitly create enums once and prevent table DDL from recreating them
    membership_role = postgresql.ENUM(
        "owner", "member", "viewer", name="membership_role", create_type=False
    )
    settlement_status = postgresql.ENUM(
        "suggested", "paid", "voided", name="settlement_status", create_type=False
    )
    membership_role.create(op.get_bind(), checkfirst=True)
    settlement_status.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("email", postgresql.CITEXT(), nullable=False, unique=True),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )

    op.create_table(
        "groups",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default=sa.text("'USD'")),
        sa.Column("version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )

    op.create_table(
        "memberships",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("role", membership_role, nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint("group_id", "user_id", name="uq_memberships_group_user"),
        sa.UniqueConstraint("group_id", "id", name="uq_memberships_group_id"),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
    )

    op.create_table(
        "settlement_batches",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("status", settlement_status, nullable=False, server_default=sa.text("'suggested'")),
        sa.Column("total_settlements", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("voided_reason", sa.Text()),
        sa.UniqueConstraint("id", "group_id", name="uq_settlement_batches_group_id"),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
    )

    op.create_table(
        "expenses",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False, server_default=sa.text("'USD'")),
        sa.Column("paid_by", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("expense_date", sa.Date(), nullable=False),
        sa.Column("memo", sa.Text()),
        sa.Column("version", sa.Integer(), nullable=False, server_default=sa.text("1")),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("amount_cents > 0", name="chk_expenses_amount_positive"),
        sa.UniqueConstraint("id", "group_id", name="uq_expenses_group_id"),
        sa.ForeignKeyConstraint(["group_id"], ["groups.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["group_id", "paid_by"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
    )

    op.create_table(
        "expense_splits",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("expense_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("membership_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("share_cents", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("share_cents >= 0", name="chk_expense_splits_share_nonnegative"),
        sa.ForeignKeyConstraint(
            ["expense_id", "group_id"],
            ["expenses.id", "expenses.group_id"],
            ondelete="CASCADE",
            deferrable=True,
            initially="DEFERRED",
        ),
        sa.ForeignKeyConstraint(
            ["group_id", "membership_id"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
    )

    op.create_table(
        "settlements",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("batch_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("from_membership", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("to_membership", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column("status", settlement_status, nullable=False, server_default=sa.text("'suggested'")),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("amount_cents > 0", name="chk_settlements_amount_positive"),
        sa.CheckConstraint("from_membership <> to_membership", name="chk_settlements_from_to_diff"),
        sa.ForeignKeyConstraint(
            ["batch_id", "group_id"],
            ["settlement_batches.id", "settlement_batches.group_id"],
            ondelete="CASCADE",
            deferrable=True,
            initially="DEFERRED",
        ),
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

    op.create_table(
        "activity_log",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("group_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("groups.id", ondelete="CASCADE")),
        sa.Column("actor_membership", postgresql.UUID(as_uuid=True), sa.ForeignKey("memberships.id", ondelete="SET NULL")),
        sa.Column("event_type", sa.Text(), nullable=False),
        sa.Column("subject_id", postgresql.UUID(as_uuid=True)),
        sa.Column("metadata", sa.JSON()),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
    )

    op.create_table(
        "idempotency_keys",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("uuid_generate_v4()")),
        sa.Column("endpoint", sa.Text(), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("request_hash", sa.Text(), nullable=False),
        sa.Column("response_body", sa.JSON()),
        sa.Column("status_code", sa.Integer()),
        sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("endpoint", "user_id", "request_hash", name="uq_idempotency_unique"),
    )

    # updated_at triggers
    op.execute(
        """
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at := now();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    for table in ["users", "groups", "expenses", "settlement_batches"]:
        op.execute(
            f"""
            CREATE TRIGGER {table}_set_updated_at
            BEFORE UPDATE ON {table}
            FOR EACH ROW EXECUTE FUNCTION set_updated_at();
            """
        )

    # split sum enforcement
    op.execute(
        """
        CREATE OR REPLACE FUNCTION enforce_expense_split_sum()
        RETURNS TRIGGER AS $$
        DECLARE
            total bigint;
            expected bigint;
        BEGIN
            SELECT SUM(share_cents) INTO total FROM expense_splits WHERE expense_id = COALESCE(NEW.expense_id, OLD.expense_id);
            SELECT amount_cents INTO expected FROM expenses WHERE id = COALESCE(NEW.expense_id, OLD.expense_id);
            IF total IS DISTINCT FROM expected THEN
                RAISE EXCEPTION 'Expense % split sum % does not equal amount %', COALESCE(NEW.expense_id, OLD.expense_id), total, expected;
            END IF;
            RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER expense_split_sum_check
        AFTER INSERT OR UPDATE OR DELETE ON expense_splits
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION enforce_expense_split_sum();
        """
    )

    op.create_index("idx_memberships_group_user", "memberships", ["group_id", "user_id"])
    op.create_index("idx_memberships_user", "memberships", ["user_id"])
    op.execute("CREATE INDEX idx_expenses_group_created ON expenses (group_id, created_at DESC)")
    op.execute("CREATE INDEX idx_expenses_group_date ON expenses (group_id, expense_date DESC)")
    op.create_index("idx_expenses_paid_by", "expenses", ["paid_by"])
    op.create_index("idx_expense_splits_expense", "expense_splits", ["expense_id"])
    op.create_index("idx_expense_splits_group_expense", "expense_splits", ["group_id", "expense_id"])
    op.execute("CREATE INDEX idx_settlement_batches_group_created ON settlement_batches (group_id, created_at DESC)")
    op.create_index("idx_settlements_batch", "settlements", ["batch_id"])
    op.create_index("idx_settlements_from", "settlements", ["from_membership"])
    op.create_index("idx_settlements_to", "settlements", ["to_membership"])
    op.execute("CREATE INDEX idx_activity_group_created ON activity_log (group_id, created_at DESC)")


def downgrade() -> None:
    op.drop_index("idx_activity_group_created", table_name="activity_log")
    op.drop_index("idx_settlements_to", table_name="settlements")
    op.drop_index("idx_settlements_from", table_name="settlements")
    op.drop_index("idx_settlements_batch", table_name="settlements")
    op.drop_index("idx_settlement_batches_group_created", table_name="settlement_batches")
    op.drop_index("idx_expense_splits_group_expense", table_name="expense_splits")
    op.drop_index("idx_expense_splits_expense", table_name="expense_splits")
    op.drop_index("idx_expenses_paid_by", table_name="expenses")
    op.drop_index("idx_expenses_group_date", table_name="expenses")
    op.drop_index("idx_expenses_group_created", table_name="expenses")
    op.drop_index("idx_memberships_user", table_name="memberships")
    op.drop_index("idx_memberships_group_user", table_name="memberships")

    op.execute("DROP TRIGGER IF EXISTS expense_split_sum_check ON expense_splits;")
    op.execute("DROP FUNCTION IF EXISTS enforce_expense_split_sum();")

    for table in ["settlement_batches", "expenses", "groups", "users"]:
        op.execute(f"DROP TRIGGER IF EXISTS {table}_set_updated_at ON {table};")
    op.execute("DROP FUNCTION IF EXISTS set_updated_at;")

    op.drop_table("idempotency_keys")
    op.drop_table("activity_log")
    op.drop_table("settlements")
    op.drop_table("expense_splits")
    op.drop_table("expenses")
    op.drop_table("settlement_batches")
    op.drop_table("memberships")
    op.drop_table("groups")
    op.drop_table("users")

    settlement_status = postgresql.ENUM(name="settlement_status")
    membership_role = postgresql.ENUM(name="membership_role")
    settlement_status.drop(op.get_bind(), checkfirst=True)
    membership_role.drop(op.get_bind(), checkfirst=True)

    op.execute('DROP EXTENSION IF EXISTS citext;')
    op.execute('DROP EXTENSION IF EXISTS "uuid-ossp";')
