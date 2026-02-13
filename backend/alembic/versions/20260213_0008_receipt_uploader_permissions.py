"""track receipt uploader for uploader-scoped permissions

Revision ID: 20260213_0008
Revises: 20260213_0007
Create Date: 2026-02-13
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "20260213_0008"
down_revision: Union[str, None] = "20260213_0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "receipt_uploads",
        sa.Column("uploaded_by_membership_id", postgresql.UUID(as_uuid=True), nullable=True),
    )

    # Backfill legacy rows with the session payer to keep existing data valid.
    op.execute(
        """
        UPDATE receipt_uploads ru
        SET uploaded_by_membership_id = ss.paid_by_membership_id
        FROM shopping_sessions ss
        WHERE ru.session_id = ss.id
        """
    )

    op.alter_column("receipt_uploads", "uploaded_by_membership_id", nullable=False)
    op.create_foreign_key(
        "fk_receipt_uploads_uploaded_by_membership",
        "receipt_uploads",
        "memberships",
        ["uploaded_by_membership_id"],
        ["id"],
        ondelete="RESTRICT",
    )

    # Keep the newest row per session before enforcing one-receipt-per-session.
    op.execute(
        """
        WITH ranked AS (
            SELECT
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY session_id
                    ORDER BY created_at DESC, id DESC
                ) AS rn
            FROM receipt_uploads
        )
        DELETE FROM receipt_uploads ru
        USING ranked r
        WHERE ru.id = r.id
          AND r.rn > 1
        """
    )
    op.create_unique_constraint(
        "uq_receipt_uploads_session",
        "receipt_uploads",
        ["session_id"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_receipt_uploads_session",
        "receipt_uploads",
        type_="unique",
    )
    op.drop_constraint(
        "fk_receipt_uploads_uploaded_by_membership",
        "receipt_uploads",
        type_="foreignkey",
    )
    op.drop_column("receipt_uploads", "uploaded_by_membership_id")
