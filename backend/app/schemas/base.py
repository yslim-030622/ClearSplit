"""Base schema classes and common types."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class BaseSchema(BaseModel):
    """Base schema with common configuration."""

    model_config = ConfigDict(
        from_attributes=True,  # Enable ORM mode (formerly orm_mode)
        json_encoders={
            UUID: str,  # Serialize UUIDs as strings in JSON
            datetime: lambda v: v.isoformat(),  # ISO-8601 format
        },
    )


class TimestampMixin:
    """Mixin for models with created_at and updated_at timestamps."""

    created_at: datetime
    updated_at: datetime


class VersionMixin:
    """Mixin for models with optimistic locking version."""

    version: int

