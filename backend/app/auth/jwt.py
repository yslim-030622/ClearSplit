"""JWT token utilities."""

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID
from uuid import uuid4

import jwt
from jwt import InvalidTokenError

from app.core.config import get_settings

settings = get_settings()

# JWT claim/type labels (not credentials or secrets).
ACCESS_TOKEN_TYPE = "access"  # nosec B105
REFRESH_TOKEN_TYPE = "refresh"  # nosec B105
BEARER_TOKEN_TYPE = "bearer"  # nosec B105


class JWTError(Exception):
    """Raised when JWT decoding or claims validation fails."""


def generate_token_jti() -> str:
    """Create a random token identifier used for refresh token rotation."""
    return uuid4().hex


def create_access_token(user_id: UUID, email: str) -> str:
    """Create a JWT access token."""
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {
        "sub": str(user_id),
        "email": email,
        "type": ACCESS_TOKEN_TYPE,
        "exp": expire,
    }
    return jwt.encode(
        payload, settings.get_jwt_secret(), algorithm=settings.jwt_algorithm
    )


def create_refresh_token(user_id: UUID, email: str) -> str:
    """Create a JWT refresh token."""
    return create_refresh_token_with_claims(user_id, email)["token"]


def create_refresh_token_with_claims(user_id: UUID, email: str) -> dict[str, Any]:
    """Create a refresh token and return details needed for persistence."""
    token_jti = generate_token_jti()
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_expire_days
    )
    payload = {
        "sub": str(user_id),
        "email": email,
        "type": REFRESH_TOKEN_TYPE,
        "jti": token_jti,
        "exp": expire,
    }
    token = jwt.encode(
        payload, settings.get_jwt_secret(), algorithm=settings.jwt_algorithm
    )
    return {
        "token": token,
        "jti": token_jti,
        "expires_at": expire,
    }


def decode_token(token: str, token_type: str = ACCESS_TOKEN_TYPE) -> dict:
    """Decode and validate a JWT token."""
    try:
        payload = jwt.decode(
            token,
            settings.get_jwt_secret(),
            algorithms=[settings.jwt_algorithm],
            options={"require": ["exp", "sub", "type"]},
        )
    except InvalidTokenError as exc:
        raise JWTError("Invalid token") from exc

    if payload.get("type") != token_type:
        raise JWTError("Invalid token type")
    return payload


def get_user_id_from_token(token: str, token_type: str = ACCESS_TOKEN_TYPE) -> UUID:
    """Extract user ID from a JWT token."""
    payload = decode_token(token, token_type)
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise JWTError("Token missing subject")
    try:
        return UUID(user_id_str)
    except (TypeError, ValueError) as exc:
        raise JWTError("Token subject must be a valid UUID") from exc


def get_refresh_token_identity(token: str) -> tuple[UUID, str]:
    """Extract user ID and JTI from a refresh token."""
    payload = decode_token(token, token_type=REFRESH_TOKEN_TYPE)
    user_id_str = payload.get("sub")
    token_jti = payload.get("jti")

    if not user_id_str:
        raise JWTError("Token missing subject")
    if not token_jti or not isinstance(token_jti, str):
        raise JWTError("Token missing jti")

    try:
        user_id = UUID(user_id_str)
    except (TypeError, ValueError) as exc:
        raise JWTError("Token subject must be a valid UUID") from exc
    return user_id, token_jti
