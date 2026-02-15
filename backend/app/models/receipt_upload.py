import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.shopping_session import ShoppingSession
    from app.models.receipt_extracted_item import ReceiptExtractedItem


class ReceiptUpload(Base):
    """Receipt upload model for storing receipt images."""

    __tablename__ = "receipt_uploads"
    __table_args__ = (UniqueConstraint("session_id", name="uq_receipt_uploads_session"),)

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
    uploaded_by_membership_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("memberships.id", ondelete="RESTRICT"),
        nullable=False,
    )
    storage_key: Mapped[str] = mapped_column(Text(), nullable=False)
    content_type: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    session: Mapped["ShoppingSession"] = relationship(back_populates="receipts")
    extracted_items: Mapped[list["ReceiptExtractedItem"]] = relationship(
        back_populates="receipt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
