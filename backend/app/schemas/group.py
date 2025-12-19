"""Group schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.base import BaseSchema, TimestampMixin, VersionMixin


class GroupRead(BaseSchema, TimestampMixin, VersionMixin):
    """Group read schema."""

    id: UUID
    name: str
    currency: str = Field(..., description="ISO 4217 currency code (e.g., USD)")
    version: int


class GroupCreate(BaseSchema):
    """Group creation schema."""

    name: str = Field(..., min_length=1, max_length=255, description="Group name")
    currency: str = Field(
        default="USD",
        min_length=3,
        max_length=3,
        description="ISO 4217 currency code (e.g., USD)",
    )

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str) -> str:
        """Validate currency code is uppercase."""
        return v.upper()


class GroupUpdate(BaseSchema):
    """Group update schema (all fields optional)."""

    name: str | None = Field(None, min_length=1, max_length=255, description="Group name")
    currency: str | None = Field(
        None,
        min_length=3,
        max_length=3,
        description="ISO 4217 currency code (e.g., USD)",
    )

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str | None) -> str | None:
        """Validate currency code is uppercase."""
        if v is not None:
            return v.upper()
        return v

