"""Settlement API routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.auth.dependencies import get_current_user
from app.core.idempotency import (
    get_idempotency_key_from_header,
    get_or_create_idempotency_key,
    store_idempotency_response,
)
from app.db.session import get_session
from app.models.settlement import SettlementStatus
from app.models.settlement import Settlement
from app.models.user import User
from app.schemas.settlement import SettlementBatchRead, SettlementRead, SettlementUpdate
from app.services.group import require_membership
from app.services.settlement import (
    compute_settlement_batch,
    get_latest_batch_with_settlements,
    update_settlement_status_to_paid,
)

router = APIRouter(tags=["settlements"])


def _serialize_batch(batch) -> SettlementBatchRead:
    batch_response = SettlementBatchRead.model_validate(batch)
    batch_response.settlements = [
        SettlementRead.model_validate(s) for s in batch.settlements or []
    ]
    return batch_response


@router.post(
    "/groups/{group_id}/settlements/compute",
    response_model=SettlementBatchRead,
    status_code=status.HTTP_201_CREATED,
)
async def compute_settlements(
    group_id: UUID,
    http_request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SettlementBatchRead:
    """Compute settlements for a group and persist a new batch."""
    await require_membership(session, group_id, current_user.id)

    # Idempotency
    idempotency_key_header = get_idempotency_key_from_header(http_request)
    request_body = {"group_id": str(group_id)}
    if idempotency_key_header:
        existing_key = await get_or_create_idempotency_key(
            session,
            endpoint=f"POST /groups/{group_id}/settlements/compute",
            user_id=current_user.id,
            request_body=request_body,
        )
        if existing_key and existing_key.response_body:
            return SettlementBatchRead.model_validate(existing_key.response_body)

    batch = await compute_settlement_batch(session, group_id)
    response_payload = _serialize_batch(batch)

    if idempotency_key_header:
        await store_idempotency_response(
            session,
            endpoint=f"POST /groups/{group_id}/settlements/compute",
            user_id=current_user.id,
            request_body=request_body,
            response_body=response_payload.model_dump(),
            status_code=201,
        )

    return response_payload


@router.get(
    "/groups/{group_id}/settlements/latest",
    response_model=SettlementBatchRead,
)
async def get_latest_settlements(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SettlementBatchRead:
    """Get the latest settlement batch for a group."""
    await require_membership(session, group_id, current_user.id)

    batch = await get_latest_batch_with_settlements(session, group_id)
    if not batch:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No settlement batches found"
        )

    return _serialize_batch(batch)


@router.patch(
    "/settlements/{settlement_id}",
    response_model=SettlementRead,
)
async def update_settlement_status(
    settlement_id: UUID,
    request: SettlementUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SettlementRead:
    """Mark a settlement as paid (debtor-only)."""
    if request.status != SettlementStatus.PAID:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only status=paid is supported",
        )

    result = await session.execute(select(Settlement).where(Settlement.id == settlement_id))
    settlement = result.scalar_one_or_none()
    if not settlement:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Settlement not found")

    acting_membership = await require_membership(
        session, settlement.group_id, current_user.id
    )

    updated = await update_settlement_status_to_paid(
        session, settlement_id=settlement_id, acting_user_membership=acting_membership
    )
    return SettlementRead.model_validate(updated)
