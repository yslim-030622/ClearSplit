"""Tests for settlement computation and updates."""

from datetime import date
from uuid import UUID, uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.settlement import (
    Settlement,
    SettlementBatch,
    SettlementPayment,
    SettlementPaymentStatus,
    SettlementStatus,
)
from app.models.shopping_item import ShoppingItem
from app.models.shopping_item_split import ShoppingItemSplit
from app.models.shopping_session import ShoppingSession, ShoppingSessionStatus
from app.models.shopping_session_participant import ShoppingSessionParticipant
from app.models.user import User
from app.tests.conftest import create_test_user


async def _create_user(session: AsyncSession, email: str) -> User:
    user = create_test_user(email=email, username=email.split("@")[0])
    session.add(user)
    await session.flush()
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
    await session.flush()
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
    await session.flush()
    await session.refresh(expense)
    return expense


async def _add_shopping_item_split(
    session: AsyncSession,
    *,
    group_id,
    paid_by,
    item_total_cents: int,
    splits: list[tuple[UUID, int]],
    status: ShoppingSessionStatus = ShoppingSessionStatus.ACTIVE,
) -> ShoppingSession:
    shopping_session = ShoppingSession(
        group_id=group_id,
        title="Grocery",
        paid_by_membership_id=paid_by,
        status=status,
    )
    session.add(shopping_session)
    await session.flush()

    participant_ids = {paid_by} | {membership_id for membership_id, _ in splits}
    for participant_id in participant_ids:
        session.add(
            ShoppingSessionParticipant(
                session_id=shopping_session.id,
                membership_id=participant_id,
            )
        )
    await session.flush()

    item = ShoppingItem(
        session_id=shopping_session.id,
        name="Item",
        quantity=1,
        total_cents=item_total_cents,
        unit_price_cents=item_total_cents,
        created_by_membership_id=paid_by,
    )
    session.add(item)
    await session.flush()

    for membership_id, share_cents in splits:
        session.add(
            ShoppingItemSplit(
                item_id=item.id,
                membership_id=membership_id,
                share_cents=share_cents,
            )
        )

    await session.flush()
    await session.refresh(shopping_session, attribute_names=["items"])
    return shopping_session


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
    
    # Add an expense so there's something to settle
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=3000,
        splits=[(m.id, 1000) for m in memberships],
    )
    
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

    count = await session.execute(
        select(func.count())
        .select_from(SettlementBatch)
        .where(SettlementBatch.group_id == group.id)
    )
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

    # Add an expense so there's something to settle
    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=2000,
        splits=[(memberships[0].id, 1000), (memberships[1].id, 1000)],
    )

    # Compute as owner then try latest/patch as outsider
    good = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(owner),
    )
    assert good.status_code == 201
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
async def test_viewer_cannot_mutate_settlement_endpoints(
    client: AsyncClient, session: AsyncSession
):
    owner = await _create_user(session, "viewer-owner@example.com")
    viewer_user = await _create_user(session, "viewer-user@example.com")

    group = Group(name="Viewer Group", currency="USD")
    session.add(group)
    await session.flush()

    owner_membership = Membership(
        group_id=group.id,
        user_id=owner.id,
        role=MembershipRole.OWNER,
    )
    viewer_membership = Membership(
        group_id=group.id,
        user_id=viewer_user.id,
        role=MembershipRole.VIEWER,
    )
    session.add_all([owner_membership, viewer_membership])
    await session.flush()

    await _add_expense(
        session,
        group_id=group.id,
        paid_by=owner_membership.id,
        amount=1000,
        splits=[(owner_membership.id, 500), (viewer_membership.id, 500)],
    )

    viewer_compute = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(viewer_user),
    )
    assert viewer_compute.status_code == 403

    owner_payment = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(owner),
        json={
            "from_membership": str(owner_membership.id),
            "to_membership": str(viewer_membership.id),
            "amount_cents": 100,
            "auto_confirm": False,
        },
    )
    assert owner_payment.status_code == 201, owner_payment.text

    viewer_confirm = await client.post(
        f"/settlement-payments/{owner_payment.json()['id']}/confirm",
        headers=_auth_header(viewer_user),
    )
    assert viewer_confirm.status_code == 403


@pytest.mark.asyncio
async def test_only_debtor_or_owner_can_mark_paid(client: AsyncClient, session: AsyncSession):
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

    # Unrelated member cannot mark paid
    denied = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(observer),
    )
    assert denied.status_code == 403

    # Debtor can mark paid
    ok = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(payer),
    )
    assert ok.status_code == 200
    assert ok.json()["status"] == "paid"


@pytest.mark.asyncio
async def test_balances_include_shopping_sessions(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "shop-a@example.com"),
        await _create_user(session, "shop-b@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)

    await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=900,
        splits=[(memberships[1].id, 900)],
        status=ShoppingSessionStatus.ACTIVE,
    )

    response = await client.get(
        f"/groups/{group.id}/balances",
        headers=_auth_header(users[0]),
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    balances = {row["membership_id"]: row["net_cents"] for row in payload["balances"]}
    assert balances[str(memberships[0].id)] == 900
    assert balances[str(memberships[1].id)] == -900
    assert payload["suggestions"][0]["amount_cents"] == 900


@pytest.mark.asyncio
async def test_shopping_session_status_filtering(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "status-a@example.com"),
        await _create_user(session, "status-b@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)

    await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=300,
        splits=[(memberships[1].id, 300)],
        status=ShoppingSessionStatus.ACTIVE,
    )
    await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=500,
        splits=[(memberships[1].id, 500)],
        status=ShoppingSessionStatus.FINALIZED,
    )
    await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=700,
        splits=[(memberships[1].id, 700)],
        status=ShoppingSessionStatus.SETTLED,
    )

    response = await client.get(
        f"/groups/{group.id}/balances",
        headers=_auth_header(users[0]),
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    balances = {row["membership_id"]: row["net_cents"] for row in payload["balances"]}
    assert balances[str(memberships[0].id)] == 800
    assert balances[str(memberships[1].id)] == -800


@pytest.mark.asyncio
async def test_balances_tolerate_split_sum_mismatch(client: AsyncClient, session: AsyncSession):
    users = [
        await _create_user(session, "mismatch-a@example.com"),
        await _create_user(session, "mismatch-b@example.com"),
    ]
    group, memberships = await _create_group_with_members(session, users)

    # Intentionally mismatched splits (700 != 1000) to simulate legacy/corrupted rows.
    await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=1000,
        splits=[(memberships[1].id, 700)],
        status=ShoppingSessionStatus.ACTIVE,
    )

    response = await client.get(
        f"/groups/{group.id}/balances",
        headers=_auth_header(users[0]),
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    balances = {row["membership_id"]: row["net_cents"] for row in payload["balances"]}
    assert balances[str(memberships[0].id)] == 1000
    assert balances[str(memberships[1].id)] == -700
    assert payload["suggestions"][0]["amount_cents"] == 700


@pytest.mark.asyncio
async def test_confirmed_payments_reduce_outstanding_balances(
    client: AsyncClient, session: AsyncSession
):
    debtor = await _create_user(session, "payment-debtor@example.com")
    creditor = await _create_user(session, "payment-creditor@example.com")
    group, memberships = await _create_group_with_members(session, [creditor, debtor])

    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=1000,
        splits=[(memberships[1].id, 1000)],
    )

    payment_create = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(debtor),
        json={
            "from_membership": str(memberships[1].id),
            "to_membership": str(memberships[0].id),
            "amount_cents": 600,
            "auto_confirm": False,
        },
    )
    assert payment_create.status_code == 201, payment_create.text
    assert payment_create.json()["status"] == "pending"

    confirm_response = await client.post(
        f"/settlement-payments/{payment_create.json()['id']}/confirm",
        headers=_auth_header(creditor),
    )
    assert confirm_response.status_code == 200, confirm_response.text
    assert confirm_response.json()["status"] == "confirmed"

    balances_response = await client.get(
        f"/groups/{group.id}/balances",
        headers=_auth_header(creditor),
    )
    assert balances_response.status_code == 200, balances_response.text
    suggestions = balances_response.json()["suggestions"]
    assert len(suggestions) == 1
    assert suggestions[0]["amount_cents"] == 400


@pytest.mark.asyncio
async def test_receiver_cannot_create_or_autoconfirm_sender_payment(
    client: AsyncClient, session: AsyncSession
):
    sender = await _create_user(session, "sender@example.com")
    receiver = await _create_user(session, "receiver2@example.com")
    group, memberships = await _create_group_with_members(session, [sender, receiver])

    forged_create = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(receiver),
        json={
            "from_membership": str(memberships[0].id),
            "to_membership": str(memberships[1].id),
            "amount_cents": 500,
            "auto_confirm": True,
        },
    )

    assert forged_create.status_code == 403


@pytest.mark.asyncio
async def test_confirming_payment_can_settle_covered_session(
    client: AsyncClient, session: AsyncSession
):
    payer = await _create_user(session, "covered-payer@example.com")
    sharer = await _create_user(session, "covered-sharer@example.com")
    group, memberships = await _create_group_with_members(session, [payer, sharer])

    shopping_session = await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=500,
        splits=[(memberships[1].id, 500)],
        status=ShoppingSessionStatus.FINALIZED,
    )

    pending_payment = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(sharer),
        json={
            "from_membership": str(memberships[1].id),
            "to_membership": str(memberships[0].id),
            "amount_cents": 500,
            "session_ids": [str(shopping_session.id)],
            "auto_confirm": False,
        },
    )
    assert pending_payment.status_code == 201, pending_payment.text
    payment_id = pending_payment.json()["id"]
    assert pending_payment.json()["status"] == "pending"

    confirmed_payment = await client.post(
        f"/settlement-payments/{payment_id}/confirm",
        headers=_auth_header(payer),
    )
    assert confirmed_payment.status_code == 200, confirmed_payment.text
    assert confirmed_payment.json()["status"] == "confirmed"

    refreshed_session = await client.get(
        f"/shopping-sessions/{shopping_session.id}",
        headers=_auth_header(payer),
    )
    assert refreshed_session.status_code == 200
    assert refreshed_session.json()["status"] == "settled"
    assert refreshed_session.json()["settled_at"] is not None


@pytest.mark.asyncio
async def test_auto_confirm_payment_without_session_ids_does_not_distort_balances(
    client: AsyncClient, session: AsyncSession
):
    payer = await _create_user(session, "no-cover-payer@example.com")
    sharer = await _create_user(session, "no-cover-sharer@example.com")
    group, memberships = await _create_group_with_members(session, [payer, sharer])

    shopping_session = await _add_shopping_item_split(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        item_total_cents=500,
        splits=[(memberships[1].id, 500)],
        status=ShoppingSessionStatus.FINALIZED,
    )

    create_response = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(sharer),
        json={
            "from_membership": str(memberships[1].id),
            "to_membership": str(memberships[0].id),
            "amount_cents": 500,
            "auto_confirm": True,
        },
    )
    assert create_response.status_code == 201, create_response.text
    assert create_response.json()["status"] == "confirmed"
    assert create_response.json()["session_ids"] == []

    balances_response = await client.get(
        f"/groups/{group.id}/balances",
        headers=_auth_header(payer),
    )
    assert balances_response.status_code == 200, balances_response.text
    payload = balances_response.json()
    balances = {row["membership_id"]: row["net_cents"] for row in payload["balances"]}
    assert balances[str(memberships[0].id)] == 0
    assert balances[str(memberships[1].id)] == 0
    assert payload["suggestions"] == []

    refreshed_session = await client.get(
        f"/shopping-sessions/{shopping_session.id}",
        headers=_auth_header(payer),
    )
    assert refreshed_session.status_code == 200
    assert refreshed_session.json()["status"] == "finalized"
    assert refreshed_session.json()["settled_at"] is None


@pytest.mark.asyncio
async def test_patch_settlement_creates_confirmed_payment_record(
    client: AsyncClient, session: AsyncSession
):
    payer = await _create_user(session, "legacy-debtor@example.com")
    receiver = await _create_user(session, "legacy-creditor@example.com")
    group, memberships = await _create_group_with_members(session, [receiver, payer])

    await _add_expense(
        session,
        group_id=group.id,
        paid_by=memberships[0].id,
        amount=750,
        splits=[(memberships[1].id, 750)],
    )

    computed = await client.post(
        f"/groups/{group.id}/settlements/compute",
        headers=_auth_header(receiver),
    )
    assert computed.status_code == 201
    settlement_id = computed.json()["settlements"][0]["id"]

    patched = await client.patch(
        f"/settlements/{settlement_id}",
        json={"status": "paid"},
        headers=_auth_header(payer),
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["status"] == "paid"

    payment_rows = await session.execute(
        select(SettlementPayment).where(SettlementPayment.group_id == group.id)
    )
    payments = list(payment_rows.scalars().all())
    assert len(payments) == 1
    assert payments[0].status == SettlementPaymentStatus.CONFIRMED
    assert payments[0].amount_cents == 750


@pytest.mark.asyncio
async def test_list_settlement_payment_history(client: AsyncClient, session: AsyncSession):
    payer = await _create_user(session, "history-payer@example.com")
    payee = await _create_user(session, "history-payee@example.com")
    group, memberships = await _create_group_with_members(session, [payer, payee])

    first_payment = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(payer),
        json={
            "from_membership": str(memberships[0].id),
            "to_membership": str(memberships[1].id),
            "amount_cents": 200,
            "auto_confirm": False,
        },
    )
    assert first_payment.status_code == 201, first_payment.text

    second_payment = await client.post(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(payer),
        json={
            "from_membership": str(memberships[0].id),
            "to_membership": str(memberships[1].id),
            "amount_cents": 100,
            "auto_confirm": True,
        },
    )
    assert second_payment.status_code == 201, second_payment.text

    history = await client.get(
        f"/groups/{group.id}/settlement-payments",
        headers=_auth_header(payee),
    )
    assert history.status_code == 200, history.text
    rows = history.json()
    assert len(rows) == 2
    assert rows[0]["amount_cents"] == 100
    assert rows[1]["amount_cents"] == 200
