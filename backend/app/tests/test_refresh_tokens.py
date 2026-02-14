"""Service-level tests for refresh token rotation invariants."""

from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.refresh_tokens import persist_refresh_token, validate_and_rotate_refresh_token
from app.models.refresh_token import RefreshToken
from app.tests.conftest import create_test_user


@pytest.mark.asyncio
async def test_validate_and_rotate_refresh_token_success_records_replacement(
    session: AsyncSession,
):
    user = create_test_user(email="refresh-service-success@example.com", username="refreshservicesuccess")
    session.add(user)
    await session.flush()

    current_jti = "current-jti-success"
    replacement_jti = "replacement-jti-success"
    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti=current_jti,
        expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
    )

    await validate_and_rotate_refresh_token(
        session,
        user_id=user.id,
        current_jti=current_jti,
        replacement_jti=replacement_jti,
        replacement_expires_at=datetime.now(tz=timezone.utc) + timedelta(days=2),
    )

    rows = await session.execute(
        select(RefreshToken).where(
            RefreshToken.user_id == user.id,
            RefreshToken.token_jti.in_([current_jti, replacement_jti]),
        )
    )
    tokens = {row.token_jti: row for row in rows.scalars().all()}
    assert set(tokens) == {current_jti, replacement_jti}
    assert tokens[current_jti].revoked_at is not None
    assert tokens[current_jti].replaced_by_jti == replacement_jti
    assert tokens[replacement_jti].revoked_at is None


@pytest.mark.asyncio
async def test_validate_and_rotate_refresh_token_rejects_expired_token(
    session: AsyncSession,
):
    user = create_test_user(email="refresh-service-expired@example.com", username="refreshserviceexpired")
    session.add(user)
    await session.flush()

    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti="expired-jti",
        expires_at=datetime.now(tz=timezone.utc) - timedelta(seconds=1),
    )

    with pytest.raises(HTTPException) as exc_info:
        await validate_and_rotate_refresh_token(
            session,
            user_id=user.id,
            current_jti="expired-jti",
            replacement_jti="replacement-expired",
            replacement_expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
        )

    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_validate_and_rotate_refresh_token_rejects_revoked_token(
    session: AsyncSession,
):
    user = create_test_user(email="refresh-service-revoked@example.com", username="refreshservicerevoked")
    session.add(user)
    await session.flush()

    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti="revoked-jti",
        expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
    )

    token_row_result = await session.execute(
        select(RefreshToken).where(RefreshToken.token_jti == "revoked-jti")
    )
    token_row = token_row_result.scalar_one()
    token_row.revoked_at = datetime.now(tz=timezone.utc)
    await session.flush()

    with pytest.raises(HTTPException) as exc_info:
        await validate_and_rotate_refresh_token(
            session,
            user_id=user.id,
            current_jti="revoked-jti",
            replacement_jti="replacement-revoked",
            replacement_expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
        )

    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_validate_and_rotate_refresh_token_rejects_same_replacement_jti(
    session: AsyncSession,
):
    user = create_test_user(email="refresh-service-same@example.com", username="refreshservicesame")
    session.add(user)
    await session.flush()

    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti="same-jti",
        expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
    )

    with pytest.raises(HTTPException) as exc_info:
        await validate_and_rotate_refresh_token(
            session,
            user_id=user.id,
            current_jti="same-jti",
            replacement_jti="same-jti",
            replacement_expires_at=datetime.now(tz=timezone.utc) + timedelta(days=1),
        )

    assert exc_info.value.status_code == 401
