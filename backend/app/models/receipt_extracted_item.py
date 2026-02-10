"""Receipt extracted item model (from OCR)."""

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import BigInteger, Float, ForeignKey, String, Text, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.db import Base


class ReceiptExtractedItem(Base):
    """Extracted item from receipt OCR.
    
    These are suggested items parsed from receipt images using OCR.
    Users can review, edit, and confirm them to create actual ShoppingItems.
    """

    __tablename__ = "receipt_extracted_items"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    receipt_upload_id: Mapped[UUID] = mapped_column(
        ForeignKey("receipt_uploads.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(Text, nullable=False)
    quantity: Mapped[int] = mapped_column(default=1, nullable=False)
    unit_price_cents: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    total_cents: Mapped[int] = mapped_column(BigInteger, nullable=False)
    raw_line: Mapped[str | None] = mapped_column(Text, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    receipt: Mapped["ReceiptUpload"] = relationship(back_populates="extracted_items")
