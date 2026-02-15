"""Authentication schemas."""


from pydantic import EmailStr, Field

from app.schemas.base import BaseSchema
from app.schemas.user import UserRead


class SignupRequest(BaseSchema):
    """User signup request schema."""

    username: str = Field(
        ...,
        min_length=3,
        max_length=30,
        description="Unique username (3-30 characters, alphanumeric and underscore/hyphen only)",
        pattern="^[a-zA-Z0-9_-]+$",
    )
    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., min_length=8, description="User password (min 8 characters)")
    first_name: str = Field(..., min_length=1, description="User first name")
    last_name: str = Field(..., min_length=1, description="User last name")


class LoginRequest(BaseSchema):
    """User login request schema.
    
    Accepts either username or email as identifier.
    """

    identifier: str = Field(
        ...,
        min_length=1,
        description="Username or email address",
    )
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
    refresh_token: str | None = Field(
        None,
        description="Rotated refresh token. Always present for current backend versions.",
    )
    token_type: str = Field(default="bearer", description="Token type")
