"""JWT token utilities."""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from jose import JWTError, jwt

from app.core.config import get_settings

settings = get_settings()


def create_access_token(user_id: UUID, email: str) -> str:
    """Create a JWT access token.

    Args:
        user_id: User UUID
        email: User email

    Returns:
        Encoded JWT token string
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    payload = {
        "sub": str(user_id),
        "email": email,
        "type": "access",
        "exp": expire,
    }
    return jwt.encode(
        payload, settings.get_jwt_secret(), algorithm=settings.jwt_algorithm
    )


def create_refresh_token(user_id: UUID, email: str) -> str:
    """Create a JWT refresh token.

    Args:
        user_id: User UUID
        email: User email

    Returns:
        Encoded JWT refresh token string
    """
    expire = datetime.now(timezone.utc) + timedelta(
        days=settings.refresh_token_expire_days
    )
    payload = {
        "sub": str(user_id),
        "email": email,
        "type": "refresh",
        "exp": expire,
    }
    return jwt.encode(
        payload, settings.get_jwt_secret(), algorithm=settings.jwt_algorithm
    )


def decode_token(token: str, token_type: str = "access") -> dict:
    """Decode and validate a JWT token.

    Args:
        token: JWT token string
        token_type: Expected token type ("access" or "refresh")

    Returns:
        Decoded token payload

    Raises:
        JWTError: If token is invalid, expired, or wrong type
    """
    try:
        payload = jwt.decode(
            token, settings.get_jwt_secret(), algorithms=[settings.jwt_algorithm]
        )
        if payload.get("type") != token_type:
            raise JWTError("Invalid token type")
        return payload
    except JWTError:
        raise


def get_user_id_from_token(token: str, token_type: str = "access") -> UUID:
    """Extract user ID from a JWT token.

    Args:
        token: JWT token string
        token_type: Expected token type ("access" or "refresh")

    Returns:
        User UUID

    Raises:
        JWTError: If token is invalid
    """
    payload = decode_token(token, token_type)
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise JWTError("Token missing subject")
    return UUID(user_id_str)

