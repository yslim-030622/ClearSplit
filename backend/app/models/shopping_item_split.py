import uuid
from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, ForeignKey, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.shopping_item import ShoppingItem


class ShoppingItemSplit(Base):
    """Split of a shopping item among participants."""

    __tablename__ = "shopping_item_splits"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    item_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("shopping_items.id", ondelete="CASCADE"),
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
        UniqueConstraint("item_id", "membership_id", name="uq_item_splits"),
        CheckConstraint("share_cents >= 0", name="chk_shopping_item_splits_share_nonnegative"),
    )

    # Relationships
    item: Mapped["ShoppingItem"] = relationship(back_populates="splits")

