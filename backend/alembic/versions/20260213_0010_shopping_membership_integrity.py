"""enforce shopping membership integrity constraints

Revision ID: 20260213_0010
Revises: 20260213_0009
Create Date: 2026-02-13
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "20260213_0010"
down_revision: Union[str, None] = "20260213_0009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM shopping_sessions ss
                LEFT JOIN memberships m ON m.id = ss.paid_by_membership_id
                WHERE m.id IS NULL OR m.group_id <> ss.group_id
            ) THEN
                RAISE EXCEPTION
                    'Cannot enforce shopping session payer integrity: found missing or cross-group paid_by_membership_id rows';
            END IF;
        END;
        $$;
        """
    )
    op.create_foreign_key(
        "fk_shopping_sessions_paid_by_membership_group",
        "shopping_sessions",
        "memberships",
        ["group_id", "paid_by_membership_id"],
        ["group_id", "id"],
        ondelete="RESTRICT",
        deferrable=True,
        initially="DEFERRED",
    )

    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM shopping_session_participants sp
                LEFT JOIN shopping_sessions ss ON ss.id = sp.session_id
                LEFT JOIN memberships m ON m.id = sp.membership_id
                WHERE ss.id IS NULL OR m.id IS NULL OR m.group_id <> ss.group_id
            ) THEN
                RAISE EXCEPTION
                    'Cannot enforce shopping participant integrity: found missing or cross-group membership rows';
            END IF;
        END;
        $$;
        """
    )
    op.create_foreign_key(
        "fk_shopping_session_participants_membership",
        "shopping_session_participants",
        "memberships",
        ["membership_id"],
        ["id"],
        ondelete="RESTRICT",
    )

    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM shopping_item_splits sis
                LEFT JOIN shopping_items si ON si.id = sis.item_id
                LEFT JOIN shopping_sessions ss ON ss.id = si.session_id
                LEFT JOIN memberships m ON m.id = sis.membership_id
                WHERE si.id IS NULL OR ss.id IS NULL OR m.id IS NULL OR m.group_id <> ss.group_id
            ) THEN
                RAISE EXCEPTION
                    'Cannot enforce shopping split integrity: found missing or cross-group membership rows';
            END IF;
        END;
        $$;
        """
    )
    op.create_foreign_key(
        "fk_shopping_item_splits_membership",
        "shopping_item_splits",
        "memberships",
        ["membership_id"],
        ["id"],
        ondelete="RESTRICT",
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION enforce_shopping_session_participant_group_match()
        RETURNS TRIGGER AS $$
        DECLARE
            session_group uuid;
            membership_group uuid;
        BEGIN
            SELECT group_id INTO session_group
            FROM shopping_sessions
            WHERE id = NEW.session_id;

            SELECT group_id INTO membership_group
            FROM memberships
            WHERE id = NEW.membership_id;

            IF session_group IS NULL OR membership_group IS NULL THEN
                RAISE EXCEPTION
                    'Cannot validate shopping session participant integrity for session_id=%, membership_id=%',
                    NEW.session_id,
                    NEW.membership_id;
            END IF;

            IF session_group <> membership_group THEN
                RAISE EXCEPTION
                    'Participant membership % does not belong to shopping session % group',
                    NEW.membership_id,
                    NEW.session_id;
            END IF;

            RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER shopping_session_participant_group_match_check
        AFTER INSERT OR UPDATE ON shopping_session_participants
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION enforce_shopping_session_participant_group_match();
        """
    )

    op.execute(
        """
        CREATE OR REPLACE FUNCTION enforce_shopping_item_split_group_match()
        RETURNS TRIGGER AS $$
        DECLARE
            item_group uuid;
            membership_group uuid;
        BEGIN
            SELECT ss.group_id INTO item_group
            FROM shopping_items si
            JOIN shopping_sessions ss ON ss.id = si.session_id
            WHERE si.id = NEW.item_id;

            SELECT group_id INTO membership_group
            FROM memberships
            WHERE id = NEW.membership_id;

            IF item_group IS NULL OR membership_group IS NULL THEN
                RAISE EXCEPTION
                    'Cannot validate shopping item split integrity for item_id=%, membership_id=%',
                    NEW.item_id,
                    NEW.membership_id;
            END IF;

            IF item_group <> membership_group THEN
                RAISE EXCEPTION
                    'Split membership % does not belong to shopping item % group',
                    NEW.membership_id,
                    NEW.item_id;
            END IF;

            RETURN NULL;
        END;
        $$ LANGUAGE plpgsql;
        """
    )
    op.execute(
        """
        CREATE CONSTRAINT TRIGGER shopping_item_split_group_match_check
        AFTER INSERT OR UPDATE ON shopping_item_splits
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION enforce_shopping_item_split_group_match();
        """
    )


def downgrade() -> None:
    op.execute(
        "DROP TRIGGER IF EXISTS shopping_item_split_group_match_check ON shopping_item_splits;"
    )
    op.execute("DROP FUNCTION IF EXISTS enforce_shopping_item_split_group_match();")

    op.execute(
        "DROP TRIGGER IF EXISTS shopping_session_participant_group_match_check ON shopping_session_participants;"
    )
    op.execute("DROP FUNCTION IF EXISTS enforce_shopping_session_participant_group_match();")

    op.drop_constraint(
        "fk_shopping_item_splits_membership",
        "shopping_item_splits",
        type_="foreignkey",
    )
    op.drop_constraint(
        "fk_shopping_session_participants_membership",
        "shopping_session_participants",
        type_="foreignkey",
    )
    op.drop_constraint(
        "fk_shopping_sessions_paid_by_membership_group",
        "shopping_sessions",
        type_="foreignkey",
    )
