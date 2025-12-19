"""Expense and ExpenseSplit schemas."""

from datetime import date, datetime
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.base import BaseSchema, TimestampMixin, VersionMixin


class ExpenseSplitCreate(BaseSchema):
    """Expense split creation schema."""

    membership_id: UUID = Field(..., description="Membership ID for this split")
    share_cents: int = Field(..., ge=0, description="Share amount in cents (>= 0)")


class ExpenseSplitRead(BaseSchema):
    """Expense split read schema."""

    id: UUID
    expense_id: UUID
    membership_id: UUID
    share_cents: int = Field(..., ge=0, description="Share amount in cents (>= 0)")
    created_at: datetime


class ExpenseRead(BaseSchema):
    """Expense read schema."""

    id: UUID
    group_id: UUID
    title: str
    amount_cents: int = Field(..., gt=0, description="Expense amount in cents (> 0)")
    currency: str = Field(..., description="ISO 4217 currency code")
    paid_by: UUID = Field(..., description="Membership ID of payer")
    expense_date: date
    memo: str | None = None
    created_at: datetime
    updated_at: datetime
    version: int
    # Optional: include splits if needed
    splits: list[ExpenseSplitRead] | None = None


class ExpenseCreateEqualSplit(BaseSchema):
    """Expense creation schema for MVP (equal split only).

    For MVP, we only support equal splits. The amount is divided equally
    among the specified membership_ids, with any remainder distributed
    to the first members in the list.
    """

    title: str = Field(..., min_length=1, max_length=500, description="Expense title")
    amount_cents: int = Field(..., gt=0, description="Expense amount in cents (> 0)")
    currency: str = Field(
        default="USD",
        min_length=3,
        max_length=3,
        description="ISO 4217 currency code",
    )
    paid_by: UUID = Field(..., description="Membership ID of payer (must be in group)")
    expense_date: date = Field(..., description="Date of expense")
    memo: str | None = Field(None, max_length=2000, description="Optional memo")
    split_among: list[UUID] = Field(
        ...,
        min_length=1,
        description="List of membership IDs to split expense among (equal split)",
    )

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str) -> str:
        """Validate currency code is uppercase."""
        return v.upper()


class ExpenseUpdate(BaseSchema):
    """Expense update schema (all fields optional, but splits must sum if provided)."""

    title: str | None = Field(None, min_length=1, max_length=500, description="Expense title")
    amount_cents: int | None = Field(None, gt=0, description="Expense amount in cents (> 0)")
    currency: str | None = Field(
        None,
        min_length=3,
        max_length=3,
        description="ISO 4217 currency code",
    )
    paid_by: UUID | None = Field(None, description="Membership ID of payer")
    expense_date: date | None = Field(None, description="Date of expense")
    memo: str | None = Field(None, max_length=2000, description="Optional memo")

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str | None) -> str | None:
        """Validate currency code is uppercase."""
        if v is not None:
            return v.upper()
        return v
