"""Tests for settlement computation and updates."""

from datetime import date
from uuid import uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.settlement import Settlement, SettlementBatch, SettlementStatus
from app.models.user import User


async def _create_user(session: AsyncSession, email: str) -> User:
    user = User(email=email, password_hash="hash")
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def _create_group_with_members(
    session: AsyncSession, users: list[User]
) -> tuple[Group, list[Membership]]:
    group = Group(name="Trip", currency="USD")
    session.add(group)
    await session.flush()
    memberships: list[Membership] = []
    roles = [MembershipRole.OWNER, MembershipRole.MEMBER, MembershipRole.MEMBER]
    for user, role in zip(users, roles):
        membership = Membership(group_id=group.id, user_id=user.id, role=role)
        session.add(membership)
        memberships.append(membership)
    await session.commit()
    await session.refresh(group)
    return group, memberships


async def _add_expense(
    session: AsyncSession,
    group_id,
    paid_by,
    amount,
    splits,
) -> Expense:
    expense = Expense(
        group_id=group_id,
        title="Expense",
        amount_cents=amount,
        currency="USD",
        paid_by=paid_by,
        expense_date=date(2024, 1, 1),
    )
    session.add(expense)
    await session.flush()
    for membership_id, share in splits:
        session.add(
            ExpenseSplit(
                expense_id=expense.id,
                group_id=group_id,
                membership_id=membership_id,
                share_cents=share,
            )
        )
    await session.commit()
    await session.refresh(expense)
    return expense


def _auth_header(user: User) -> dict[str, str]:
    token = create_access_token(user.id, user.email)
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_compute_settlements_generates_transfers(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "a@example.com"),
        await _create_user(session, "b@example.com"),
        await _create_user(session, "c@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)

    # Expense 1: A pays 3000, split equally among 3 (net: A +2000, B -1000, C -1000)
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=3000,
        splits=[(m.id, 1000) for m in memberships],
    )
    # Expense 2: B pays 1500, split between B and C (net adjust: B +750, C -750)
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[1].id,
        amount=1500,
        splits=[(memberships[1].id, 750), (memberships[2].id, 750)],
    )

    resp = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(users[0]),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    settlements = data["settlements"]
    assert data["total_settlements"] == 2
    # Expected transfers: C->A 1750, B->A 250 (order deterministic)
    amounts = sorted([(s["from_membership"], s["to_membership"], s["amount_cents"]) for s in settlements], key=lambda x: x[2], reverse=True)
    assert amounts[0][2] == 1750
    assert amounts[1][2] == 250


@pytest.mark.asyncio
async def test_settlement_snapshot_immutability(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "d@example.com"),
        await _create_user(session, "e@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)

    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=2000,
        splits=[(memberships[0].id, 1000), (memberships[1].id, 1000)],
    )

    first = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(users[0]),
    )
    assert first.status_code == 201
    first_batch_id = first.json()["id"]

    # New expense changes balances
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[1].id,
        amount=1000,
        splits=[(memberships[1].id, 500), (memberships[0].id, 500)],
    )
    second = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(users[0]),
    )
    assert second.status_code == 201
    assert second.json()["id"] != first_batch_id

    # Reload first batch to ensure unchanged
    result = await session.execute(
        select(SettlementBatch).where(SettlementBatch.id == first_batch_id)
    )
    original_batch = result.scalar_one()
    await session.refresh(original_batch, attribute_names=["settlements"])
    original_amounts = [s.amount_cents for s in original_batch.settlements]
    assert original_amounts == [1000]


@pytest.mark.asyncio
async def test_compute_idempotency(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "idempotent1@example.com"),
        await _create_user(session, "idempotent2@example.com"),
        await _create_user(session, "idempotent3@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)
    user = users[0]
    key = str(uuid4())

    resp1 = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers={**_auth_header(user), "Idempotency-Key": key},
    )
    resp2 = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers={**_auth_header(user), "Idempotency-Key": key},
    )
    assert resp1.status_code == resp2.status_code == 201
    assert resp1.json()["id"] == resp2.json()["id"]

    count = await session.execute(select(func.count()).select_from(SettlementBatch))
    assert count.scalar() == 1


@pytest.mark.asyncio
async def test_permissions_enforced(client: AsyncClient, session: AsyncSession):
    owner = await _create_user(session, "owner@example.com")
    outsider = await _create_user(session, "outsider@example.com")
    member = await _create_user(session, "member@example.com")
    group, memberships = await _create_group_with_members(session, [owner, member])

    resp = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(outsider),
    )
    assert resp.status_code == 403

    # Compute as owner then try latest/patch as outsider
    good = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(owner),
    )
    settlement_id = good.json()["settlements"][0]["id"]

    latest = await client.get(
        f"/groups/{group.id}/settlements/latest",
        headers=_auth_header(outsider),
    )
    assert latest.status_code == 403

    patch = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(outsider),
    )
    assert patch.status_code == 403


@pytest.mark.asyncio
async def test_only_debtor_can_mark_paid(client: AsyncClient, session: AsyncSession):
    payer = await _create_user(session, "payer@example.com")
    receiver = await _create_user(session, "receiver@example.com")
    observer = await _create_user(session, "observer@example.com")
    group, memberships = await _create_group_with_members(session, [payer, receiver, observer])

    # Simple imbalance: payer owes receiver 500
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[1].id,
        amount=500,
        splits=[(memberships[0].id, 500)],
    )

    computed = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(receiver),
    )
    settlement_id = computed.json()["settlements"][0]["id"]

    # Non-debtor cannot mark paid
    denied = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(receiver),
    )
    assert denied.status_code == 403

    # Debtor marks paid
    ok = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(payer),
    )
    assert ok.status_code == 200
    assert ok.json()["status"] == "paid"
