"""Settlement batch and settlement schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.models.settlement import SettlementPaymentStatus, SettlementStatus
from app.schemas.base import BaseSchema


class SettlementRead(BaseSchema):
    """Settlement read schema."""

    id: UUID
    batch_id: UUID
    from_membership: UUID = Field(..., description="Membership ID of payer")
    to_membership: UUID = Field(..., description="Membership ID of payee")
    amount_cents: int = Field(..., gt=0, description="Settlement amount in cents (> 0)")
    status: SettlementStatus
    created_at: datetime


class SettlementSuggestionRead(BaseSchema):
    """Live settlement suggestion read schema."""

    from_membership: UUID = Field(..., description="Membership ID of payer")
    to_membership: UUID = Field(..., description="Membership ID of payee")
    amount_cents: int = Field(..., gt=0, description="Suggested transfer amount in cents (> 0)")


class MembershipBalanceRead(BaseSchema):
    """Per-membership net balance."""

    membership_id: UUID
    net_cents: int = Field(
        ...,
        description="Net balance in cents (positive means should receive, negative means owes)",
    )


class GroupBalancesRead(BaseSchema):
    """Live balances and suggestions."""

    group_id: UUID
    computed_at: datetime
    balances: list[MembershipBalanceRead]
    suggestions: list[SettlementSuggestionRead]


class SettlementBatchRead(BaseSchema):
    """Settlement batch read schema."""

    id: UUID
    group_id: UUID
    status: SettlementStatus
    total_settlements: int = Field(..., ge=0, description="Number of settlements in batch")
    created_at: datetime
    updated_at: datetime
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


class SettlementPaymentCreate(BaseSchema):
    """Create settlement payment request."""

    from_membership: UUID
    to_membership: UUID
    amount_cents: int = Field(..., gt=0)
    note: str | None = Field(None, max_length=1000)
    session_ids: list[UUID] | None = Field(
        None, description="Optional shopping session IDs this payment covers"
    )
    auto_confirm: bool = Field(
        default=False,
        description="If true, payment is immediately confirmed",
    )


class SettlementPaymentRead(BaseSchema):
    """Settlement payment read schema."""

    id: UUID
    group_id: UUID
    from_membership: UUID
    to_membership: UUID
    amount_cents: int
    status: SettlementPaymentStatus
    note: str | None = None
    sent_at: datetime | None = None
    confirmed_at: datetime | None = None
    created_at: datetime
    session_ids: list[UUID] = Field(default_factory=list)
