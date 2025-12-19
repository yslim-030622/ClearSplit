"""Expense and ExpenseSplit schemas."""

from datetime import date, datetime
from uuid import UUID

from pydantic import Field, field_validator, model_validator

from app.schemas.base import BaseSchema, TimestampMixin, VersionMixin


class ExpenseSplitRead(BaseSchema):
    """Expense split read schema."""

    id: UUID
    expense_id: UUID
    membership_id: UUID
    share_cents: int = Field(..., ge=0, description="Share amount in cents (>= 0)")
    created_at: datetime


class ExpenseSplitCreate(BaseSchema):
    """Expense split creation schema."""

    membership_id: UUID = Field(..., description="Membership ID for this split")
    share_cents: int = Field(..., ge=0, description="Share amount in cents (>= 0)")


class ExpenseRead(BaseSchema, TimestampMixin, VersionMixin):
    """Expense read schema."""

    id: UUID
    group_id: UUID
    title: str
    amount_cents: int = Field(..., gt=0, description="Expense amount in cents (> 0)")
    currency: str = Field(..., description="ISO 4217 currency code")
    paid_by: UUID = Field(..., description="Membership ID of payer")
    expense_date: date
    memo: str | None = None
    version: int
    # Optional: include splits if needed
    splits: list[ExpenseSplitRead] | None = None


class ExpenseCreate(BaseSchema):
    """Expense creation schema."""

    title: str = Field(..., min_length=1, max_length=500, description="Expense title")
    amount_cents: int = Field(..., gt=0, description="Expense amount in cents (> 0)")
    currency: str = Field(
        default="USD",
        min_length=3,
        max_length=3,
        description="ISO 4217 currency code",
    )
    paid_by: UUID = Field(..., description="Membership ID of payer")
    expense_date: date = Field(..., description="Date of expense")
    memo: str | None = Field(None, max_length=2000, description="Optional memo")
    splits: list[ExpenseSplitCreate] = Field(
        ...,
        min_length=1,
        description="List of expense splits (must sum to amount_cents)",
    )

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str) -> str:
        """Validate currency code is uppercase."""
        return v.upper()

    @field_validator("splits")
    @classmethod
    def validate_splits_not_empty(cls, v: list[ExpenseSplitCreate]) -> list[ExpenseSplitCreate]:
        """Validate that splits list is not empty."""
        if not v:
            raise ValueError("At least one split is required")
        return v

    @model_validator(mode="after")
    def validate_splits_sum(self) -> "ExpenseCreate":
        """Validate that splits sum to amount_cents."""
        if self.splits:
            total = sum(split.share_cents for split in self.splits)
            if total != self.amount_cents:
                raise ValueError(
                    f"Splits sum ({total} cents) must equal amount_cents ({self.amount_cents} cents)"
                )
        return self


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
    splits: list[ExpenseSplitCreate] | None = Field(
        None,
        min_length=1,
        description="List of expense splits (must sum to amount_cents if provided)",
    )

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str | None) -> str | None:
        """Validate currency code is uppercase."""
        if v is not None:
            return v.upper()
        return v

    @field_validator("splits")
    @classmethod
    def validate_splits_not_empty(cls, v: list[ExpenseSplitCreate] | None) -> list[ExpenseSplitCreate] | None:
        """Validate that splits are not empty if provided."""
        if v is not None and not v:
            raise ValueError("At least one split is required")
        return v

    @model_validator(mode="after")
    def validate_splits_sum(self) -> "ExpenseUpdate":
        """Validate that splits sum to amount_cents if both are provided."""
        if self.splits is not None and self.amount_cents is not None:
            total = sum(split.share_cents for split in self.splits)
            if total != self.amount_cents:
                raise ValueError(
                    f"Splits sum ({total} cents) must equal amount_cents ({self.amount_cents} cents)"
                )
        return self

