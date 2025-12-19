import uuid
from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, ForeignKey, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.expense import Expense
    from app.models.membership import Membership


class ExpenseSplit(Base):
    """Expense split model for individual member shares of expenses."""

    __tablename__ = "expense_splits"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    expense_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    membership_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    share_cents: Mapped[int] = mapped_column(BigInteger(), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("share_cents >= 0", name="chk_expense_splits_share_nonnegative"),
        # Composite FKs are handled at DB level via deferred constraints
        # ForeignKey(["expense_id", "group_id"], ["expenses.id", "expenses.group_id"], ondelete="CASCADE"),
        # ForeignKey(["group_id", "membership_id"], ["memberships.group_id", "memberships.id"], ondelete="RESTRICT"),
    )

    # Relationships
    expense: Mapped["Expense"] = relationship(back_populates="splits")
    membership: Mapped["Membership"] = relationship()

