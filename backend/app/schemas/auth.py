"""Authentication schemas."""

from uuid import UUID

from pydantic import EmailStr, Field

from app.schemas.base import BaseSchema
from app.schemas.user import UserRead


class SignupRequest(BaseSchema):
    """User signup request schema."""

    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., min_length=8, description="User password (min 8 characters)")


class LoginRequest(BaseSchema):
    """User login request schema."""

    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., description="User password")


class RefreshTokenRequest(BaseSchema):
    """Refresh token request schema."""

    refresh_token: str = Field(..., description="Refresh token")


class TokenResponse(BaseSchema):
    """Token response schema."""

    access_token: str = Field(..., description="JWT access token")
    refresh_token: str = Field(..., description="JWT refresh token")
    token_type: str = Field(default="bearer", description="Token type")
    user: UserRead = Field(..., description="User information")


class RefreshTokenResponse(BaseSchema):
    """Refresh token response schema."""

    access_token: str = Field(..., description="New JWT access token")
    token_type: str = Field(default="bearer", description="Token type")

