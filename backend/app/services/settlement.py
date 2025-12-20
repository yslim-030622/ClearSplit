"""Settlement computation and status update services."""

from __future__ import annotations

from collections import defaultdict
from typing import Iterable
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.membership import Membership
from app.models.settlement import Settlement, SettlementBatch, SettlementStatus


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


async def _compute_balances(
    session: AsyncSession, group_id: UUID, memberships: Iterable[Membership]
) -> dict[UUID, int]:
    """Return net balance per membership_id (paid - owed)."""
    paid = defaultdict(int)
    owed = defaultdict(int)

    paid_rows = await session.execute(
        select(Expense.paid_by, func.coalesce(func.sum(Expense.amount_cents), 0))
        .where(Expense.group_id == group_id)
        .group_by(Expense.paid_by)
    )
    for member_id, total in paid_rows.all():
        paid[member_id] = total

    owed_rows = await session.execute(
        select(ExpenseSplit.membership_id, func.coalesce(func.sum(ExpenseSplit.share_cents), 0))
        .where(ExpenseSplit.group_id == group_id)
        .group_by(ExpenseSplit.membership_id)
    )
    for member_id, total in owed_rows.all():
        owed[member_id] = total

    balances: dict[UUID, int] = {}
    for membership in memberships:
        balances[membership.id] = paid[membership.id] - owed[membership.id]
    return balances


def _generate_transfers(balances: dict[UUID, int]) -> list[tuple[UUID, UUID, int]]:
    """Return list of (from_membership, to_membership, amount_cents) transfers."""
    creditors = sorted(
        [(mid, net) for mid, net in balances.items() if net > 0],
        key=lambda x: x[1],
        reverse=True,
    )
    debtors = sorted(
        [(mid, -net) for mid, net in balances.items() if net < 0],
        key=lambda x: x[1],
        reverse=True,
    )

    transfers: list[tuple[UUID, UUID, int]] = []
    i = j = 0
    while i < len(debtors) and j < len(creditors):
        debtor_id, owed = debtors[i]
        creditor_id, credit = creditors[j]
        amount = min(owed, credit)
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


async def compute_settlement_batch(
    session: AsyncSession, group_id: UUID
) -> SettlementBatch:
    """Compute settlements for a group and persist a new batch + settlements."""
    memberships = await _get_group_memberships(session, group_id)
    balances = await _compute_balances(session, group_id, memberships)
    transfers = _generate_transfers(balances)

    # Create batch and settlements
    # Use begin_nested if already in a transaction, otherwise begin
    if session.in_transaction():
        async with session.begin_nested():
            batch = SettlementBatch(
                group_id=group_id, total_settlements=len(transfers), status=SettlementStatus.SUGGESTED
            )
            session.add(batch)
            await session.flush()  # ensure batch.id is available

            for debtor_id, creditor_id, amount in transfers:
                settlement = Settlement(
                    batch_id=batch.id,
                    group_id=group_id,
                    from_membership=debtor_id,
                    to_membership=creditor_id,
                    amount_cents=amount,
                    status=SettlementStatus.SUGGESTED,
                )
                session.add(settlement)
    else:
        async with session.begin():
            batch = SettlementBatch(
                group_id=group_id, total_settlements=len(transfers), status=SettlementStatus.SUGGESTED
            )
            session.add(batch)
            await session.flush()  # ensure batch.id is available

            for debtor_id, creditor_id, amount in transfers:
                settlement = Settlement(
                    batch_id=batch.id,
                    group_id=group_id,
                    from_membership=debtor_id,
                    to_membership=creditor_id,
                    amount_cents=amount,
                    status=SettlementStatus.SUGGESTED,
                )
                session.add(settlement)

    await session.refresh(batch, attribute_names=["settlements"])
    # Ensure deterministic ordering for responses
    batch.settlements = sorted(
        batch.settlements,
        key=lambda s: (s.from_membership, s.to_membership, s.amount_cents, s.id),
    )
    return batch


async def get_latest_batch_with_settlements(
    session: AsyncSession, group_id: UUID
) -> SettlementBatch | None:
    result = await session.execute(
        select(SettlementBatch)
        .options(selectinload(SettlementBatch.settlements))
        .where(SettlementBatch.group_id == group_id)
        .order_by(SettlementBatch.created_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def update_settlement_status_to_paid(
    session: AsyncSession, settlement_id: UUID, acting_user_membership: Membership
) -> Settlement:
    result = await session.execute(
        select(Settlement)
        .options(selectinload(Settlement.batch))
        .where(Settlement.id == settlement_id)
    )
    settlement = result.scalar_one_or_none()
    if not settlement:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Settlement not found")

    # Authorization: user must belong to the group and be the debtor (from_membership)
    if settlement.group_id != acting_user_membership.group_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a group member")
    if settlement.from_membership != acting_user_membership.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the debtor can mark a settlement as paid",
        )

    if settlement.status == SettlementStatus.PAID:
        return settlement

    if settlement.status != SettlementStatus.SUGGESTED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only suggested settlements can be marked paid",
        )

    settlement.status = SettlementStatus.PAID
    await session.commit()
    await session.refresh(settlement)
    return settlement
