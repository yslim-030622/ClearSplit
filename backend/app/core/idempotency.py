"""Idempotency key handling utilities."""

import json
from uuid import UUID

from fastapi import HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.idempotency_key import IdempotencyKey
from app.services.expense import compute_request_hash


async def get_or_create_idempotency_key(
    session: AsyncSession,
    endpoint: str,
    user_id: UUID,
    request_body: dict,
) -> IdempotencyKey | None:
    """Get existing idempotency key or return None if new.

    Args:
        session: Database session
        endpoint: API endpoint path
        user_id: User UUID
        request_body: Request body as dict

    Returns:
        Existing IdempotencyKey if found, None if new request
    """
    request_hash = compute_request_hash(request_body)

    result = await session.execute(
        select(IdempotencyKey).where(
            IdempotencyKey.endpoint == endpoint,
            IdempotencyKey.user_id == user_id,
            IdempotencyKey.request_hash == request_hash,
        )
    )
    return result.scalar_one_or_none()


async def store_idempotency_response(
    session: AsyncSession,
    endpoint: str,
    user_id: UUID,
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
    from fastapi.encoders import jsonable_encoder
    
    request_hash = compute_request_hash(request_body)
    
    # Normalize response_body to ensure JSONB compatibility
    # Converts UUID -> str, Enum -> value, datetime -> ISO string
    normalized_response = jsonable_encoder(response_body)

    idempotency_key = IdempotencyKey(
        endpoint=endpoint,
        user_id=user_id,
        request_hash=request_hash,
        response_body=normalized_response,
        status_code=status_code,
    )
    session.add(idempotency_key)
    await session.commit()


def get_idempotency_key_from_header(request: Request) -> str | None:
    """Extract idempotency key from request header.

    Args:
        request: FastAPI request

    Returns:
        Idempotency key string or None
    """
    return request.headers.get("Idempotency-Key")

