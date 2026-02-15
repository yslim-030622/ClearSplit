import uuid
from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, ForeignKey, Integer, Text, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.membership import Membership
    from app.models.shopping_session import ShoppingSession
    from app.models.shopping_item_split import ShoppingItemSplit


class ShoppingItem(Base):
    """Shopping item (line item from receipt)."""

    __tablename__ = "shopping_items"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="gen_random_uuid()",
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("shopping_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(Text(), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer(), nullable=False, server_default="1")
    unit_price_cents: Mapped[int | None] = mapped_column(BigInteger(), nullable=True)
    total_cents: Mapped[int] = mapped_column(BigInteger(), nullable=False)
    created_by_membership_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("memberships.id", ondelete="RESTRICT"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("quantity >= 1", name="chk_shopping_items_quantity_positive"),
        CheckConstraint("unit_price_cents IS NULL OR unit_price_cents >= 0", name="chk_shopping_items_unit_price_nonnegative"),
        CheckConstraint("total_cents > 0", name="chk_shopping_items_total_positive"),
    )

    # Relationships
    session: Mapped["ShoppingSession"] = relationship(back_populates="items")
    created_by_membership: Mapped["Membership"] = relationship(foreign_keys=[created_by_membership_id])
    splits: Mapped[list["ShoppingItemSplit"]] = relationship(
        back_populates="item",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
