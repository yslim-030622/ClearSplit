import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import CheckConstraint, Date, ForeignKey, Numeric, String, Text, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.group import Group
    from app.models.shopping_session_participant import ShoppingSessionParticipant
    from app.models.receipt_upload import ReceiptUpload
    from app.models.shopping_item import ShoppingItem


class ShoppingSession(Base):
    """Shopping session model for grocery trips."""

    __tablename__ = "shopping_sessions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(Text(), nullable=False)
    shopping_date: Mapped[date | None] = mapped_column(Date(), nullable=True)
    total_amount: Mapped[Decimal | None] = mapped_column(
        Numeric(10, 2),
        nullable=True,
        comment="Optional total amount for quick splits without itemization",
    )
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    paid_by_membership_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    group: Mapped["Group"] = relationship(back_populates="shopping_sessions")
    participants: Mapped[list["ShoppingSessionParticipant"]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    receipts: Mapped[list["ReceiptUpload"]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    items: Mapped[list["ShoppingItem"]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

