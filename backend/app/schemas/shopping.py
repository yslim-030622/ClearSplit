"""Shopping session schemas."""

from datetime import date, datetime
from uuid import UUID

from pydantic import Field, field_validator, model_validator

from app.schemas.base import BaseSchema


# ============================================================================
# Receipt Extracted Item Schemas (OCR Results)
# ============================================================================


class ReceiptExtractedItemRead(BaseSchema):
    """Receipt extracted item read schema (OCR result)."""

    id: UUID
    receipt_upload_id: UUID
    name: str
    quantity: int
    unit_price_cents: int | None
    total_cents: int
    raw_line: str | None
    confidence: float | None
    created_at: datetime


# ============================================================================
# Receipt Upload schemas
# ============================================================================


class ReceiptUploadRead(BaseSchema):
    """Receipt upload read schema."""

    id: UUID
    session_id: UUID
    storage_key: str
    content_type: str
    created_at: datetime


class ReceiptDownloadURLResponse(BaseSchema):
    """Response schema for presigned receipt download URL."""

    receipt_upload_id: UUID
    expires_in_seconds: int
    url: str


class ReceiptDeleteResponse(BaseSchema):
    """Response schema for receipt deletion."""

    receipt_upload_id: UUID
    deleted: bool


# ============================================================================
# Shopping Item Split schemas
# ============================================================================


class ShoppingItemSplitRead(BaseSchema):
    """Shopping item split read schema."""

    id: UUID
    item_id: UUID
    membership_id: UUID
    share_cents: int = Field(..., ge=0, description="Share amount in cents (>= 0)")


# ============================================================================
# Shopping Item schemas
# ============================================================================


class ShoppingItemCreate(BaseSchema):
    """Shopping item creation schema."""

    name: str = Field(..., min_length=1, max_length=500, description="Item name")
    quantity: int = Field(default=1, ge=1, description="Quantity (>= 1)")
    unit_price_cents: int | None = Field(None, ge=0, description="Unit price in cents (>= 0)")
    total_cents: int | None = Field(None, gt=0, description="Total price in cents (> 0)")

    @model_validator(mode="after")
    def validate_total(self):
        """Ensure total_cents is provided, or computed from unit_price * quantity."""
        if self.total_cents is None:
            if self.unit_price_cents is None:
                raise ValueError("Either total_cents or unit_price_cents must be provided")
            self.total_cents = self.unit_price_cents * self.quantity
        return self


class ShoppingItemRead(BaseSchema):
    """Shopping item read schema."""

    id: UUID
    session_id: UUID
    name: str
    quantity: int
    unit_price_cents: int | None
    total_cents: int
    created_at: datetime
    splits: list[ShoppingItemSplitRead] = Field(default_factory=list)


# ============================================================================
# Shopping Session Participant schemas
# ============================================================================


class ParticipantSetRequest(BaseSchema):
    """Request schema for setting session participants."""

    participant_membership_ids: list[UUID] = Field(
        ...,
        min_length=1,
        description="List of membership IDs who participated in this shopping session",
    )


class ShoppingSessionParticipantRead(BaseSchema):
    """Shopping session participant read schema."""

    id: UUID
    session_id: UUID
    membership_id: UUID
    created_at: datetime


# ============================================================================
# Shopping Session schemas
# ============================================================================


class ShoppingSessionCreate(BaseSchema):
    """Shopping session creation schema."""

    title: str = Field(..., min_length=1, max_length=500, description="Session title (e.g., 'Costco')")
    shopping_date: date | None = Field(None, description="Date of shopping trip")
    total_amount: float | None = Field(None, ge=0, description="Optional total amount for quick splits")
    paid_by: UUID = Field(..., description="Membership ID of payer (must be in group)")


class ShoppingSessionRead(BaseSchema):
    """Shopping session read schema."""

    id: UUID
    group_id: UUID
    title: str
    shopping_date: date | None
    total_amount: float | None
    currency: str
    paid_by_membership_id: UUID
    created_at: datetime
    participants: list[ShoppingSessionParticipantRead] = Field(default_factory=list)
    receipts: list[ReceiptUploadRead] = Field(default_factory=list)
    items: list[ShoppingItemRead] = Field(default_factory=list)


# ============================================================================
# Sharers schemas
# ============================================================================


class SharersSetRequest(BaseSchema):
    """Request schema for setting item sharers."""

    membership_ids: list[UUID] = Field(
        ...,
        min_length=1,
        description="List of membership IDs who share this item (must be session participants)",
    )


class SharersSetResponse(BaseSchema):
    """Response schema after setting sharers with computed splits."""

    item_id: UUID
    total_cents: int
    splits: list[ShoppingItemSplitRead]
