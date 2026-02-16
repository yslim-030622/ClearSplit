"""Settlement and balances API routes."""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.core.idempotency import (
    get_idempotency_key_from_header,
    get_or_create_idempotency_key,
    store_idempotency_response,
)
from app.db.session import get_session
from app.models.settlement import Settlement, SettlementPayment, SettlementStatus
from app.models.user import User
from app.schemas.settlement import (
    GroupBalancesRead,
    MembershipBalanceRead,
    SettlementBatchRead,
    SettlementPaymentCreate,
    SettlementPaymentRead,
    SettlementRead,
    SettlementSuggestionRead,
    SettlementUpdate,
)
from app.services.group import require_membership
from app.services.settlement import (
    compute_group_balances,
    compute_settlement_batch,
    confirm_settlement_payment,
    create_settlement_payment,
    get_latest_batch_with_settlements,
    list_settlement_payments,
    update_settlement_status_to_paid,
)

router = APIRouter(tags=["settlements"])


def _serialize_batch(batch) -> SettlementBatchRead:
    batch_response = SettlementBatchRead.model_validate(batch)
    batch_response.settlements = [
        SettlementRead.model_validate(settlement) for settlement in batch.settlements or []
    ]
    return batch_response


def _serialize_payment(payment: SettlementPayment) -> SettlementPaymentRead:
    return SettlementPaymentRead(
        id=payment.id,
        group_id=payment.group_id,
        from_membership=payment.from_membership,
        to_membership=payment.to_membership,
        amount_cents=payment.amount_cents,
        status=payment.status,
        note=payment.note,
        sent_at=payment.sent_at,
        confirmed_at=payment.confirmed_at,
        created_at=payment.created_at,
        session_ids=[link.session_id for link in payment.session_links or []],
    )


@router.get(
    "/groups/{group_id}/balances",
    response_model=GroupBalancesRead,
)
async def get_group_balances(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupBalancesRead:
    """Get live balances and transfer suggestions for a group."""

    await require_membership(session, group_id, current_user.id)
    memberships, balances, transfers = await compute_group_balances(session, group_id)

    balance_rows = [
        MembershipBalanceRead(membership_id=membership.id, net_cents=balances[membership.id])
        for membership in sorted(memberships, key=lambda row: str(row.id))
    ]
    suggestions = [
        SettlementSuggestionRead(
            from_membership=from_membership,
            to_membership=to_membership,
            amount_cents=amount_cents,
        )
        for from_membership, to_membership, amount_cents in transfers
    ]
    return GroupBalancesRead(
        group_id=group_id,
        computed_at=datetime.now(tz=timezone.utc),
        balances=balance_rows,
        suggestions=suggestions,
    )


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
    """Compute settlements for a group and persist a new immutable batch."""

    await require_membership(
        session,
        group_id,
        current_user.id,
        allow_viewer=False,
    )

    idempotency_key_header = get_idempotency_key_from_header(http_request)
    request_body = {"group_id": str(group_id)}
    if idempotency_key_header:
        existing_key = await get_or_create_idempotency_key(
            session,
            endpoint=f"POST /groups/{group_id}/settlements/compute",
            user_id=current_user.id,
            idempotency_key=idempotency_key_header,
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
            idempotency_key=idempotency_key_header,
            request_body=request_body,
            response_body=response_payload.model_dump(mode="json"),
            status_code=201,
        )

    await session.commit()
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
    """Get the latest persisted settlement batch for a group."""

    await require_membership(session, group_id, current_user.id)
    batch = await get_latest_batch_with_settlements(session, group_id)
    if not batch:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No settlement batches found"
        )
    return _serialize_batch(batch)


@router.post(
    "/groups/{group_id}/settlement-payments",
    response_model=SettlementPaymentRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_payment(
    group_id: UUID,
    request: SettlementPaymentCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SettlementPaymentRead:
    """Create a settlement payment in pending or confirmed state."""

    acting_membership = await require_membership(
        session,
        group_id,
        current_user.id,
        allow_viewer=False,
    )
    payment = await create_settlement_payment(
        session,
        group_id=group_id,
        acting_membership=acting_membership,
        from_membership=request.from_membership,
        to_membership=request.to_membership,
        amount_cents=request.amount_cents,
        note=request.note,
        session_ids=request.session_ids,
        auto_confirm=request.auto_confirm,
    )
    await session.commit()
    return _serialize_payment(payment)


@router.post(
    "/settlement-payments/{payment_id}/confirm",
    response_model=SettlementPaymentRead,
)
async def confirm_payment(
    payment_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SettlementPaymentRead:
    """Confirm a pending settlement payment."""

    payment_group_result = await session.execute(
        select(SettlementPayment.group_id).where(SettlementPayment.id == payment_id)
    )
    payment_group_id = payment_group_result.scalar_one_or_none()
    if not payment_group_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Settlement payment not found",
        )

    acting_membership = await require_membership(
        session,
        payment_group_id,
        current_user.id,
        allow_viewer=False,
    )
    payment = await confirm_settlement_payment(
        session,
        payment_id=payment_id,
        acting_membership=acting_membership,
    )
    await session.commit()
    return _serialize_payment(payment)


@router.get(
    "/groups/{group_id}/settlement-payments",
    response_model=list[SettlementPaymentRead],
)
async def get_payment_history(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[SettlementPaymentRead]:
    """List settlement payment history for a group."""

    await require_membership(session, group_id, current_user.id)
    payments = await list_settlement_payments(session, group_id)
    return [_serialize_payment(payment) for payment in payments]


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
    """Backward-compatible settlement action endpoint."""

    if request.status != SettlementStatus.PAID:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only status=paid is supported",
        )

    settlement_result = await session.execute(
        select(Settlement).where(Settlement.id == settlement_id)
    )
    settlement = settlement_result.scalar_one_or_none()
    if not settlement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Settlement not found",
        )

    acting_membership = await require_membership(
        session,
        settlement.group_id,
        current_user.id,
        allow_viewer=False,
    )
    updated = await update_settlement_status_to_paid(
        session,
        settlement_id=settlement_id,
        acting_user_membership=acting_membership,
    )
    await session.commit()
    return SettlementRead.model_validate(updated)
