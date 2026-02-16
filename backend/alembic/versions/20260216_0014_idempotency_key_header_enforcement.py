"""enforce idempotency uniqueness by header key value

Revision ID: 20260216_0014
Revises: 20260215_0013
Create Date: 2026-02-16
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


# revision identifiers, used by Alembic.
revision: str = "20260216_0014"
down_revision: Union[str, None] = "20260215_0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "idempotency_keys",
        sa.Column("idempotency_key", sa.Text(), nullable=True),
    )
    op.execute(
        """
        UPDATE idempotency_keys
        SET idempotency_key = request_hash
        WHERE idempotency_key IS NULL;
        """
    )
    op.alter_column("idempotency_keys", "idempotency_key", nullable=False)
    op.drop_constraint("uq_idempotency_unique", "idempotency_keys", type_="unique")
    op.create_unique_constraint(
        "uq_idempotency_unique",
        "idempotency_keys",
        ["endpoint", "user_id", "idempotency_key"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_idempotency_unique", "idempotency_keys", type_="unique")
    op.create_unique_constraint(
        "uq_idempotency_unique",
        "idempotency_keys",
        ["endpoint", "user_id", "request_hash"],
    )
    op.drop_column("idempotency_keys", "idempotency_key")
