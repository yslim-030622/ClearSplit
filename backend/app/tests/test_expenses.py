"""Tests for expenses endpoints."""

import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.auth.password import hash_password
from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User
from app.services.expense import calculate_equal_splits


@pytest.mark.asyncio
async def test_create_expense_equal_split(client: AsyncClient, session: AsyncSession):
    """Test creating an expense with equal splits."""
    # Create users
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    user3 = User(email="user3@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2, user3])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.commit()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Create expense
    response = await client.post(
        f"/groups/{group.id}/expenses",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Dinner",
            "amount_cents": 1000,
            "currency": "USD",
            "paid_by": str(membership1.id),
            "expense_date": str(date.today()),
            "split_among": [str(membership1.id), str(membership2.id), str(membership3.id)],
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Dinner"
    assert data["amount_cents"] == 1000
    assert len(data["splits"]) == 3

    # Verify splits sum to amount
    total = sum(split["share_cents"] for split in data["splits"])
    assert total == 1000


@pytest.mark.asyncio
async def test_equal_split_remainder(client: AsyncClient, session: AsyncSession):
    """Test equal split with remainder distribution."""
    # Create users
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    user3 = User(email="user3@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2, user3])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.commit()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Create expense with amount that doesn't divide evenly (1000 cents / 3 = 333 remainder 1)
    response = await client.post(
        f"/groups/{group.id}/expenses",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Lunch",
            "amount_cents": 1000,
            "currency": "USD",
            "paid_by": str(membership1.id),
            "expense_date": str(date.today()),
            "split_among": [str(membership1.id), str(membership2.id), str(membership3.id)],
        },
    )

    assert response.status_code == 201
    data = response.json()
    splits = data["splits"]

    # Verify remainder rule: first person gets 334, others get 333
    # Total: 334 + 333 + 333 = 1000
    share_amounts = sorted([s["share_cents"] for s in splits], reverse=True)
    assert share_amounts == [334, 333, 333]
    assert sum(share_amounts) == 1000


@pytest.mark.asyncio
async def test_idempotent_create_expense(client: AsyncClient, session: AsyncSession):
    """Test idempotent expense creation with same Idempotency-Key."""
    # Create user
    user = User(email="user@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.commit()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Generate idempotency key
    idempotency_key = str(uuid.uuid4())

    # Create expense first time
    response1 = await client.post(
        f"/groups/{group.id}/expenses",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Idempotency-Key": idempotency_key,
        },
        json={
            "title": "Dinner",
            "amount_cents": 5000,
            "currency": "USD",
            "paid_by": str(membership.id),
            "expense_date": str(date.today()),
            "split_among": [str(membership.id)],
        },
    )

    assert response1.status_code == 201
    expense_id_1 = response1.json()["id"]

    # Create same expense again with same idempotency key
    response2 = await client.post(
        f"/groups/{group.id}/expenses",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Idempotency-Key": idempotency_key,
        },
        json={
            "title": "Dinner",
            "amount_cents": 5000,
            "currency": "USD",
            "paid_by": str(membership.id),
            "expense_date": str(date.today()),
            "split_among": [str(membership.id)],
        },
    )

    assert response2.status_code == 201
    expense_id_2 = response2.json()["id"]

    # Should return same expense
    assert expense_id_1 == expense_id_2

    # Verify only one expense was created
    from sqlalchemy import select

    result = await session.execute(
        select(Expense).where(Expense.group_id == group.id, Expense.title == "Dinner")
    )
    expenses = list(result.scalars().all())
    assert len(expenses) == 1


@pytest.mark.asyncio
async def test_create_expense_invalid_payer(client: AsyncClient, session: AsyncSession):
    """Test creating expense with payer not in group."""
    # Create users
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2])
    await session.commit()

    # Create groups
    group1 = Group(name="Group 1", currency="USD")
    group2 = Group(name="Group 2", currency="USD")
    session.add_all([group1, group2])
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group1.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group2.id, user_id=user2.id, role=MembershipRole.OWNER
    )
    session.add_all([membership1, membership2])
    await session.commit()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Try to create expense in group1 with payer from group2
    response = await client.post(
        f"/groups/{group1.id}/expenses",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Dinner",
            "amount_cents": 1000,
            "currency": "USD",
            "paid_by": str(membership2.id),  # Payer from different group
            "expense_date": str(date.today()),
            "split_among": [str(membership1.id)],
        },
    )

    assert response.status_code == 400
    assert "not found in group" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_create_expense_invalid_split_member(
    client: AsyncClient, session: AsyncSession
):
    """Test creating expense with split member not in group."""
    # Create users
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2])
    await session.commit()

    # Create groups
    group1 = Group(name="Group 1", currency="USD")
    group2 = Group(name="Group 2", currency="USD")
    session.add_all([group1, group2])
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group1.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group2.id, user_id=user2.id, role=MembershipRole.OWNER
    )
    session.add_all([membership1, membership2])
    await session.commit()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Try to create expense with split member from different group
    response = await client.post(
        f"/groups/{group1.id}/expenses",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Dinner",
            "amount_cents": 1000,
            "currency": "USD",
            "paid_by": str(membership1.id),
            "expense_date": str(date.today()),
            "split_among": [str(membership1.id), str(membership2.id)],  # membership2 from different group
        },
    )

    assert response.status_code == 400
    assert "not found in group" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_list_group_expenses(client: AsyncClient, session: AsyncSession):
    """Test listing expenses for a group."""
    # Create user
    user = User(email="user@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Create expenses manually
    expense1 = Expense(
        group_id=group.id,
        title="Expense 1",
        amount_cents=1000,
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
    )
    expense2 = Expense(
        group_id=group.id,
        title="Expense 2",
        amount_cents=2000,
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
    )
    session.add_all([expense1, expense2])
    await session.commit()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # List expenses
    response = await client.get(
        f"/groups/{group.id}/expenses",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    titles = [e["title"] for e in data]
    assert "Expense 1" in titles
    assert "Expense 2" in titles


@pytest.mark.asyncio
async def test_get_expense(client: AsyncClient, session: AsyncSession):
    """Test getting a specific expense."""
    # Create user
    user = User(email="user@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Create expense
    expense = Expense(
        group_id=group.id,
        title="Test Expense",
        amount_cents=5000,
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
        memo="Test memo",
    )
    session.add(expense)
    await session.flush()

    # Create split
    split = ExpenseSplit(
        expense_id=expense.id,
        group_id=group.id,
        membership_id=membership.id,
        share_cents=5000,
    )
    session.add(split)
    await session.commit()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Get expense
    response = await client.get(
        f"/expenses/{expense.id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(expense.id)
    assert data["title"] == "Test Expense"
    assert data["memo"] == "Test memo"
    assert len(data["splits"]) == 1


@pytest.mark.asyncio
async def test_get_expense_not_member(client: AsyncClient, session: AsyncSession):
    """Test getting expense when user is not a member of the group."""
    # Create users
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership for user1 only
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    session.add(membership1)
    await session.flush()

    # Create expense
    expense = Expense(
        group_id=group.id,
        title="Test Expense",
        amount_cents=1000,
        currency="USD",
        paid_by=membership1.id,
        expense_date=date.today(),
    )
    session.add(expense)
    await session.commit()

    # Get access token for user2 (not a member)
    access_token = create_access_token(user2.id, user2.email)

    # Try to get expense
    response = await client.get(
        f"/expenses/{expense.id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 403
    assert "not a member" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_calculate_equal_splits():
    """Test equal split calculation function."""
    # Test case: 1000 cents / 3 people = 334, 333, 333
    splits = calculate_equal_splits(1000, 3)
    assert splits == [334, 333, 333]
    assert sum(splits) == 1000

    # Test case: 100 cents / 3 people = 34, 33, 33
    splits = calculate_equal_splits(100, 3)
    assert splits == [34, 33, 33]
    assert sum(splits) == 100

    # Test case: 1000 cents / 2 people = 500, 500
    splits = calculate_equal_splits(1000, 2)
    assert splits == [500, 500]
    assert sum(splits) == 1000

    # Test case: 1 cent / 3 people = 1, 0, 0
    splits = calculate_equal_splits(1, 3)
    assert splits == [1, 0, 0]
    assert sum(splits) == 1

