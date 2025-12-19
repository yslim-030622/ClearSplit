"""Settlement batch and settlement schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.models.settlement import SettlementStatus
from app.schemas.base import BaseSchema, TimestampMixin, VersionMixin


class SettlementRead(BaseSchema):
    """Settlement read schema."""

    id: UUID
    batch_id: UUID
    from_membership: UUID = Field(..., description="Membership ID of payer")
    to_membership: UUID = Field(..., description="Membership ID of payee")
    amount_cents: int = Field(..., gt=0, description="Settlement amount in cents (> 0)")
    status: SettlementStatus
    created_at: datetime


class SettlementBatchRead(BaseSchema, TimestampMixin, VersionMixin):
    """Settlement batch read schema."""

    id: UUID
    group_id: UUID
    status: SettlementStatus
    total_settlements: int = Field(..., ge=0, description="Number of settlements in batch")
    version: int
    voided_reason: str | None = None
    # Optional: include settlements if needed
    settlements: list[SettlementRead] | None = None


class SettlementBatchCreate(BaseSchema):
    """Settlement batch creation schema.

    Note: Settlement batches are typically created by the settlement engine,
    not directly by clients. This schema is for internal use.
    """

    group_id: UUID = Field(..., description="Group ID for settlement batch")


class SettlementBatchUpdate(BaseSchema):
    """Settlement batch update schema (status and voided_reason only, as per immutability)."""

    status: SettlementStatus | None = Field(None, description="New settlement batch status")
    voided_reason: str | None = Field(
        None,
        max_length=1000,
        description="Reason for voiding (if status is voided)",
    )


class SettlementUpdate(BaseSchema):
    """Settlement update schema (status only, as per immutability)."""

    status: SettlementStatus = Field(..., description="New settlement status")

