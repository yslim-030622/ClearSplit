"""User schemas."""

from uuid import UUID

from pydantic import EmailStr, Field

from app.schemas.base import BaseSchema


class UserRead(BaseSchema):
    """User read schema (minimal fields for client)."""

    id: UUID
    username: str
    email: EmailStr
    first_name: str
    last_name: str


class UserCreate(BaseSchema):
    """User creation schema."""

    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., min_length=8, description="User password (min 8 characters)")


class UserUpdate(BaseSchema):
    """User update schema (all fields optional)."""

    email: EmailStr | None = Field(None, description="User email address")
    password: str | None = Field(None, min_length=8, description="User password (min 8 characters)")

