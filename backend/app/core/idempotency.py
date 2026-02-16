"""Idempotency key handling utilities."""

from uuid import UUID

from fastapi import HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.idempotency_key import IdempotencyKey
from app.services.expense import compute_request_hash

MAX_IDEMPOTENCY_KEY_LENGTH = 255


async def get_or_create_idempotency_key(
    session: AsyncSession,
    endpoint: str,
    user_id: UUID,
    idempotency_key: str,
    request_body: dict,
) -> IdempotencyKey | None:
    """Get existing idempotency row for a key or return None when new.

    Args:
        session: Database session
        endpoint: API endpoint path
        user_id: User UUID
        idempotency_key: Client-provided idempotency key value
        request_body: Request body as dict

    Returns:
        Existing IdempotencyKey if found, None if new request
    """
    request_hash = compute_request_hash(request_body)

    result = await session.execute(
        select(IdempotencyKey).where(
            IdempotencyKey.endpoint == endpoint,
            IdempotencyKey.user_id == user_id,
            IdempotencyKey.idempotency_key == idempotency_key,
        )
    )
    existing = result.scalar_one_or_none()
    if existing is None:
        return None

    if existing.request_hash != request_hash:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Idempotency-Key reuse with a different request payload is not allowed"
            ),
        )
    return existing


async def store_idempotency_response(
    session: AsyncSession,
    endpoint: str,
    user_id: UUID,
    idempotency_key: str,
    request_body: dict,
    response_body: dict,
    status_code: int,
) -> None:
    """Store idempotency key with response.

    Args:
        session: Database session
        endpoint: API endpoint path
        user_id: User UUID
        request_body: Request body as dict
        response_body: Response body as dict
        status_code: HTTP status code
    """
    request_hash = compute_request_hash(request_body)

    idempotency_row = IdempotencyKey(
        endpoint=endpoint,
        user_id=user_id,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
        response_body=response_body,
        status_code=status_code,
    )
    session.add(idempotency_row)
    await session.flush()


def get_idempotency_key_from_header(request: Request) -> str | None:
    """Extract idempotency key from request header.

    Args:
        request: FastAPI request

    Returns:
        Idempotency key string or None
    """
    header_value = request.headers.get("Idempotency-Key")
    if header_value is None:
        return None

    normalized = header_value.strip()
    if not normalized:
        return None

    if len(normalized) > MAX_IDEMPOTENCY_KEY_LENGTH:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Idempotency-Key is too long (max {MAX_IDEMPOTENCY_KEY_LENGTH} characters)"
            ),
        )
    return normalized
