"""Settlement and balances computation services."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
import logging
from typing import Iterable
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.membership import Membership, MembershipRole
from app.models.settlement import (
    Settlement,
    SettlementBatch,
    SettlementPayment,
    SettlementPaymentSession,
    SettlementPaymentStatus,
    SettlementStatus,
)
from app.models.shopping_item import ShoppingItem
from app.models.shopping_session import ShoppingSession, ShoppingSessionStatus

logger = logging.getLogger(__name__)


async def _get_group_memberships(
    session: AsyncSession, group_id: UUID
) -> list[Membership]:
    result = await session.execute(
        select(Membership)
        .options(selectinload(Membership.user))
        .where(Membership.group_id == group_id)
    )
    memberships = list(result.scalars().all())
    if not memberships:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Group has no members"
        )
    return memberships


def _warn_non_zero_net(
    group_id: UUID,
    balances: dict[UUID, int],
    diagnostics: dict[str, object],
) -> None:
    net_total = sum(balances.values())
    if net_total == 0:
        return

    non_zero = sorted(
        ((str(mid), amount) for mid, amount in balances.items() if amount != 0),
        key=lambda row: abs(row[1]),
        reverse=True,
    )[:10]
    logger.warning(
        "Balance computation net sum mismatch group_id=%s net_total_cents=%s top_non_zero_memberships=%s diagnostics=%s",
        group_id,
        net_total,
        non_zero,
        diagnostics,
    )


async def _compute_balances(
    session: AsyncSession, group_id: UUID, memberships: Iterable[Membership]
) -> tuple[dict[UUID, int], dict[str, object]]:
    """Return net balance per membership_id (paid - owed), with diagnostics."""

    paid = defaultdict(int)
    owed = defaultdict(int)
    diagnostics: dict[str, object] = {
        "expense_paid_total_cents": 0,
        "expense_owed_total_cents": 0,
        "shopping_paid_total_cents": 0,
        "shopping_owed_total_cents": 0,
        "confirmed_payment_total_cents": 0,
        "shopping_sessions_considered": 0,
        "shopping_items_skipped_without_splits": 0,
        "shopping_items_split_sum_mismatches": [],
        "confirmed_payments_applied": 0,
    }

    # Expenses - payer contributes paid amount
    paid_rows = await session.execute(
        select(Expense.paid_by, func.coalesce(func.sum(Expense.amount_cents), 0))
        .where(Expense.group_id == group_id)
        .group_by(Expense.paid_by)
    )
    for member_id, total in paid_rows.all():
        total_int = int(total or 0)
        paid[member_id] += total_int
        diagnostics["expense_paid_total_cents"] = int(
            diagnostics["expense_paid_total_cents"]
        ) + total_int

    # Expenses - split members contribute owed amounts
    owed_rows = await session.execute(
        select(
            ExpenseSplit.membership_id,
            func.coalesce(func.sum(ExpenseSplit.share_cents), 0),
        )
        .where(ExpenseSplit.group_id == group_id)
        .group_by(ExpenseSplit.membership_id)
    )
    for member_id, total in owed_rows.all():
        total_int = int(total or 0)
        owed[member_id] += total_int
        diagnostics["expense_owed_total_cents"] = int(
            diagnostics["expense_owed_total_cents"]
        ) + total_int

    # Shopping sessions - only active/finalized contribute to balances
    session_rows = await session.execute(
        select(ShoppingSession)
        .where(
            ShoppingSession.group_id == group_id,
            ShoppingSession.status.in_(
                [ShoppingSessionStatus.ACTIVE, ShoppingSessionStatus.FINALIZED]
            ),
        )
        .options(selectinload(ShoppingSession.items).selectinload(ShoppingItem.splits))
    )
    shopping_sessions = list(session_rows.scalars().all())
    diagnostics["shopping_sessions_considered"] = len(shopping_sessions)

    mismatch_samples: list[dict[str, object]] = []
    for shopping_session in shopping_sessions:
        payer_id = shopping_session.paid_by_membership_id
        for item in shopping_session.items:
            if not item.splits:
                diagnostics["shopping_items_skipped_without_splits"] = int(
                    diagnostics["shopping_items_skipped_without_splits"]
                ) + 1
                continue

            item_total = int(item.total_cents)
            paid[payer_id] += item_total
            diagnostics["shopping_paid_total_cents"] = int(
                diagnostics["shopping_paid_total_cents"]
            ) + item_total

            split_sum = 0
            for split in item.splits:
                share = int(split.share_cents)
                split_sum += share
                owed[split.membership_id] += share
                diagnostics["shopping_owed_total_cents"] = int(
                    diagnostics["shopping_owed_total_cents"]
                ) + share

            if split_sum != item_total and len(mismatch_samples) < 5:
                mismatch_samples.append(
                    {
                        "session_id": str(shopping_session.id),
                        "item_id": str(item.id),
                        "item_total_cents": item_total,
                        "split_sum_cents": split_sum,
                    }
                )
    diagnostics["shopping_items_split_sum_mismatches"] = mismatch_samples

    balances: dict[UUID, int] = {}
    for membership in memberships:
        balances[membership.id] = paid[membership.id] - owed[membership.id]

    # Apply confirmed payments as reductions to outstanding balances.
    payment_rows = await session.execute(
        select(SettlementPayment).where(
            SettlementPayment.group_id == group_id,
            SettlementPayment.status == SettlementPaymentStatus.CONFIRMED,
        )
    )
    payments = list(payment_rows.scalars().all())
    diagnostics["confirmed_payments_applied"] = len(payments)
    for payment in payments:
        amount = int(payment.amount_cents)
        balances.setdefault(payment.from_membership, 0)
        balances.setdefault(payment.to_membership, 0)
        balances[payment.from_membership] += amount
        balances[payment.to_membership] -= amount
        diagnostics["confirmed_payment_total_cents"] = int(
            diagnostics["confirmed_payment_total_cents"]
        ) + amount

    _warn_non_zero_net(group_id, balances, diagnostics)
    return balances, diagnostics


def _generate_transfers(balances: dict[UUID, int]) -> list[tuple[UUID, UUID, int]]:
    """Return list of (from_membership, to_membership, amount_cents) transfers."""

    creditors = sorted(
        ((mid, net) for mid, net in balances.items() if net > 0),
        key=lambda row: (-row[1], str(row[0])),
    )
    debtors = sorted(
        ((mid, -net) for mid, net in balances.items() if net < 0),
        key=lambda row: (-row[1], str(row[0])),
    )

    transfers: list[tuple[UUID, UUID, int]] = []
    i = j = 0
    while i < len(debtors) and j < len(creditors):
        debtor_id, owed = debtors[i]
        creditor_id, credit = creditors[j]
        amount = min(owed, credit)
        if amount > 0:
            transfers.append((debtor_id, creditor_id, amount))

        owed -= amount
        credit -= amount
        debtors[i] = (debtor_id, owed)
        creditors[j] = (creditor_id, credit)

        if owed == 0:
            i += 1
        if credit == 0:
            j += 1

    return transfers


async def compute_group_balances(
    session: AsyncSession, group_id: UUID
) -> tuple[list[Membership], dict[UUID, int], list[tuple[UUID, UUID, int]]]:
    """Compute live balances and transfer suggestions without persisting a batch."""

    memberships = await _get_group_memberships(session, group_id)
    balances, _ = await _compute_balances(session, group_id, memberships)
    transfers = _generate_transfers(balances)
    return memberships, balances, transfers


async def compute_settlement_batch(
    session: AsyncSession, group_id: UUID
) -> SettlementBatch:
    """Compute settlements for a group and persist a new batch + settlements."""

    _, _, transfers = await compute_group_balances(session, group_id)
    latest_version_result = await session.execute(
        select(func.coalesce(func.max(SettlementBatch.version), 0)).where(
            SettlementBatch.group_id == group_id
        )
    )
    latest_version = int(latest_version_result.scalar_one() or 0)
    now = datetime.now(tz=timezone.utc)

    batch = SettlementBatch(
        group_id=group_id,
        total_settlements=len(transfers),
        status=SettlementStatus.SUGGESTED,
        version=latest_version + 1,
        created_at=now,
        updated_at=now,
    )
    session.add(batch)
    await session.flush()

    for debtor_id, creditor_id, amount in transfers:
        session.add(
            Settlement(
                batch_id=batch.id,
                group_id=group_id,
                from_membership=debtor_id,
                to_membership=creditor_id,
                amount_cents=amount,
                status=SettlementStatus.SUGGESTED,
            )
        )
    await session.flush()

    await session.refresh(batch, attribute_names=["settlements"])
    batch.settlements = sorted(
        batch.settlements,
        key=lambda s: (
            s.amount_cents * -1,
            str(s.from_membership),
            str(s.to_membership),
            str(s.id),
        ),
    )
    return batch


async def get_latest_batch_with_settlements(
    session: AsyncSession, group_id: UUID
) -> SettlementBatch | None:
    result = await session.execute(
        select(SettlementBatch)
        .options(selectinload(SettlementBatch.settlements))
        .where(SettlementBatch.group_id == group_id)
        .order_by(SettlementBatch.version.desc(), SettlementBatch.created_at.desc())
        .limit(1)
    )
    batch = result.scalar_one_or_none()
    if batch and batch.settlements:
        batch.settlements = sorted(
            batch.settlements,
            key=lambda s: (
                s.amount_cents * -1,
                str(s.from_membership),
                str(s.to_membership),
                str(s.id),
            ),
        )
    return batch


async def _resolve_covered_sessions(
    session: AsyncSession,
    group_id: UUID,
    session_ids: list[UUID] | None,
) -> list[ShoppingSession]:
    if session_ids is None:
        return []

    if session_ids:
        result = await session.execute(
            select(ShoppingSession)
            .where(
                ShoppingSession.group_id == group_id,
                ShoppingSession.id.in_(session_ids),
            )
            .options(selectinload(ShoppingSession.items).selectinload(ShoppingItem.splits))
        )
        sessions = list(result.scalars().all())
        if len(sessions) != len(set(session_ids)):
            found = {row.id for row in sessions}
            missing = [sid for sid in session_ids if sid not in found]
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unknown shopping session(s) for group: {missing}",
            )
        return sessions

    return []


async def _validate_memberships_for_payment(
    session: AsyncSession,
    group_id: UUID,
    from_membership: UUID,
    to_membership: UUID,
) -> None:
    if from_membership == to_membership:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="from_membership and to_membership must differ",
        )

    result = await session.execute(
        select(Membership.id).where(
            Membership.group_id == group_id,
            Membership.id.in_([from_membership, to_membership]),
        )
    )
    found = set(result.scalars().all())
    if from_membership not in found or to_membership not in found:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Payment memberships must belong to the group",
        )


def _authorize_payment_action(
    acting_membership: Membership,
    *,
    from_membership: UUID,
) -> None:
    if acting_membership.role == MembershipRole.OWNER:
        return
    if acting_membership.id == from_membership:
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Only the payment sender or a group owner can create this settlement payment",
    )


def _authorize_payment_confirmation(
    acting_membership: Membership,
    *,
    to_membership: UUID,
) -> None:
    if acting_membership.role == MembershipRole.OWNER:
        return
    if acting_membership.id == to_membership:
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Only the payment receiver or a group owner can confirm payment",
    )


async def _evaluate_covered_sessions_for_settlement(
    session: AsyncSession,
    group_id: UUID,
    covered_session_ids: list[UUID],
) -> None:
    if not covered_session_ids:
        return

    result = await session.execute(
        select(ShoppingSession)
        .where(
            ShoppingSession.group_id == group_id,
            ShoppingSession.id.in_(covered_session_ids),
        )
        .options(selectinload(ShoppingSession.items).selectinload(ShoppingItem.splits))
    )
    sessions = list(result.scalars().all())
    now = datetime.now(tz=timezone.utc)

    for shopping_session in sessions:
        # Build raw session net from items/splits.
        session_balances: defaultdict[UUID, int] = defaultdict(int)
        has_split_items = False
        for item in shopping_session.items:
            if not item.splits:
                continue
            has_split_items = True
            item_total = int(item.total_cents)
            session_balances[shopping_session.paid_by_membership_id] += item_total
            for split in item.splits:
                session_balances[split.membership_id] -= int(split.share_cents)

        if not has_split_items:
            continue

        # Apply confirmed payments that explicitly cover this session.
        payment_result = await session.execute(
            select(SettlementPayment)
            .join(
                SettlementPaymentSession,
                SettlementPayment.id == SettlementPaymentSession.payment_id,
            )
            .where(
                SettlementPayment.group_id == group_id,
                SettlementPayment.status == SettlementPaymentStatus.CONFIRMED,
                SettlementPaymentSession.session_id == shopping_session.id,
            )
        )
        for payment in payment_result.scalars().all():
            amount = int(payment.amount_cents)
            session_balances[payment.from_membership] += amount
            session_balances[payment.to_membership] -= amount

        is_fully_settled = all(amount == 0 for amount in session_balances.values())
        if is_fully_settled and shopping_session.status != ShoppingSessionStatus.SETTLED:
            shopping_session.status = ShoppingSessionStatus.SETTLED
            shopping_session.settled_at = now
            if shopping_session.finalized_at is None:
                shopping_session.finalized_at = now

    await session.flush()


def _serialize_payment_sessions(payment: SettlementPayment) -> list[UUID]:
    return [link.session_id for link in (payment.session_links or [])]


async def create_settlement_payment(
    session: AsyncSession,
    *,
    group_id: UUID,
    acting_membership: Membership,
    from_membership: UUID,
    to_membership: UUID,
    amount_cents: int,
    note: str | None,
    session_ids: list[UUID] | None,
    auto_confirm: bool,
) -> SettlementPayment:
    """Create a settlement payment, optionally confirmed immediately."""

    if acting_membership.group_id != group_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a group member",
        )
    await _validate_memberships_for_payment(
        session,
        group_id,
        from_membership=from_membership,
        to_membership=to_membership,
    )
    _authorize_payment_action(
        acting_membership,
        from_membership=from_membership,
    )
    if auto_confirm and (
        acting_membership.role != MembershipRole.OWNER
        and acting_membership.id != from_membership
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payment sender or a group owner can auto-confirm settlement payments",
        )

    covered_sessions = await _resolve_covered_sessions(
        session,
        group_id,
        session_ids=session_ids,
    )
    now = datetime.now(tz=timezone.utc)
    payment = SettlementPayment(
        group_id=group_id,
        from_membership=from_membership,
        to_membership=to_membership,
        amount_cents=amount_cents,
        status=(
            SettlementPaymentStatus.CONFIRMED
            if auto_confirm
            else SettlementPaymentStatus.PENDING
        ),
        note=note,
        sent_at=now,
        confirmed_at=now if auto_confirm else None,
        created_at=now,
    )
    session.add(payment)
    await session.flush()

    for covered_session in covered_sessions:
        session.add(
            SettlementPaymentSession(
                payment_id=payment.id,
                session_id=covered_session.id,
            )
        )
    await session.flush()

    if auto_confirm:
        await compute_settlement_batch(session, group_id)
        await _evaluate_covered_sessions_for_settlement(
            session,
            group_id,
            [covered_session.id for covered_session in covered_sessions],
        )

    await session.refresh(payment, attribute_names=["session_links"])
    return payment


async def confirm_settlement_payment(
    session: AsyncSession,
    *,
    payment_id: UUID,
    acting_membership: Membership,
) -> SettlementPayment:
    """Confirm an existing pending settlement payment."""

    result = await session.execute(
        select(SettlementPayment)
        .options(selectinload(SettlementPayment.session_links))
        .where(SettlementPayment.id == payment_id)
    )
    payment = result.scalar_one_or_none()
    if not payment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Settlement payment not found",
        )

    if acting_membership.group_id != payment.group_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a group member",
        )
    _authorize_payment_confirmation(
        acting_membership,
        to_membership=payment.to_membership,
    )

    if payment.status == SettlementPaymentStatus.CONFIRMED:
        return payment
    if payment.status != SettlementPaymentStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only pending payments can be confirmed",
        )

    now = datetime.now(tz=timezone.utc)
    payment.status = SettlementPaymentStatus.CONFIRMED
    payment.confirmed_at = now
    payment.sent_at = payment.sent_at or now
    await session.flush()

    await compute_settlement_batch(session, payment.group_id)
    await _evaluate_covered_sessions_for_settlement(
        session,
        payment.group_id,
        _serialize_payment_sessions(payment),
    )
    await session.refresh(payment, attribute_names=["session_links"])
    return payment


async def list_settlement_payments(
    session: AsyncSession, group_id: UUID
) -> list[SettlementPayment]:
    """List settlement payments for a group by most recent first."""

    result = await session.execute(
        select(SettlementPayment)
        .options(selectinload(SettlementPayment.session_links))
        .where(SettlementPayment.group_id == group_id)
        .order_by(SettlementPayment.created_at.desc(), SettlementPayment.sent_at.desc())
    )
    return list(result.scalars().all())


async def update_settlement_status_to_paid(
    session: AsyncSession, settlement_id: UUID, acting_user_membership: Membership
) -> Settlement:
    """Legacy API support: mark settlement paid and persist a confirmed payment."""

    result = await session.execute(
        select(Settlement)
        .options(selectinload(Settlement.batch))
        .where(Settlement.id == settlement_id)
    )
    settlement = result.scalar_one_or_none()
    if not settlement:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Settlement not found",
        )

    if settlement.group_id != acting_user_membership.group_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not a group member",
        )
    if (
        acting_user_membership.role != MembershipRole.OWNER
        and acting_user_membership.id != settlement.from_membership
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the debtor or a group owner can mark a settlement as paid",
        )

    if settlement.status == SettlementStatus.PAID:
        return settlement
    if settlement.status != SettlementStatus.SUGGESTED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only suggested settlements can be marked paid",
        )

    settlement.status = SettlementStatus.PAID
    await session.flush()

    await create_settlement_payment(
        session,
        group_id=settlement.group_id,
        acting_membership=acting_user_membership,
        from_membership=settlement.from_membership,
        to_membership=settlement.to_membership,
        amount_cents=settlement.amount_cents,
        note=f"Legacy settlement payment for {settlement.id}",
        session_ids=None,
        auto_confirm=True,
    )
    await session.refresh(settlement)
    return settlement
