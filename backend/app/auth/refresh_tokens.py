"""Refresh token persistence helpers for rotation and replay protection."""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.refresh_token import RefreshToken


def _invalid_refresh_token() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired refresh token",
    )


async def persist_refresh_token(
    session: AsyncSession,
    *,
    user_id: UUID,
    token_jti: str,
    expires_at: datetime,
) -> None:
    session.add(
        RefreshToken(
            user_id=user_id,
            token_jti=token_jti,
            expires_at=expires_at,
        )
    )
    await session.flush()


async def validate_and_rotate_refresh_token(
    session: AsyncSession,
    *,
    user_id: UUID,
    current_jti: str,
    replacement_jti: str,
    replacement_expires_at: datetime,
) -> None:
    now = datetime.now(tz=timezone.utc)
    if current_jti == replacement_jti:
        raise _invalid_refresh_token()

    result = await session.execute(
        select(RefreshToken)
        .where(
            RefreshToken.user_id == user_id,
            RefreshToken.token_jti == current_jti,
        )
        .with_for_update()
    )
    stored = result.scalar_one_or_none()
    if not stored:
        raise _invalid_refresh_token()
    if stored.revoked_at is not None:
        raise _invalid_refresh_token()
    if stored.expires_at <= now:
        raise _invalid_refresh_token()

    stored.revoked_at = now
    stored.replaced_by_jti = replacement_jti

    await persist_refresh_token(
        session,
        user_id=user_id,
        token_jti=replacement_jti,
        expires_at=replacement_expires_at,
    )
