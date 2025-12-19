"""Integration tests for SQLAlchemy models.

These tests require a running Postgres database (via docker-compose).
Mark with pytest.mark.integration if you want to skip them in unit test runs.
"""

import uuid
from datetime import date, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    ActivityLog,
    Expense,
    ExpenseSplit,
    Group,
    IdempotencyKey,
    Membership,
    MembershipRole,
    Settlement,
    SettlementBatch,
    SettlementStatus,
    User,
)


@pytest.mark.asyncio
async def test_user_model(session: AsyncSession):
    """Test User model creation and retrieval."""
    user = User(
        email="test@example.com",
        password_hash="hashed_password",
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)

    assert user.id is not None
    assert isinstance(user.id, uuid.UUID)
    assert user.email == "test@example.com"
    assert user.password_hash == "hashed_password"
    assert isinstance(user.created_at, datetime)
    assert isinstance(user.updated_at, datetime)


@pytest.mark.asyncio
async def test_group_model(session: AsyncSession):
    """Test Group model creation."""
    group = Group(
        name="Test Group",
        currency="USD",
    )
    session.add(group)
    await session.commit()
    await session.refresh(group)

    assert group.id is not None
    assert isinstance(group.id, uuid.UUID)
    assert group.name == "Test Group"
    assert group.currency == "USD"
    assert group.version == 1
    assert isinstance(group.created_at, datetime)


@pytest.mark.asyncio
async def test_membership_model(session: AsyncSession):
    """Test Membership model with relationships."""
    user = User(email="member@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id,
        user_id=user.id,
        role=MembershipRole.MEMBER,
    )
    session.add(membership)
    await session.commit()
    await session.refresh(membership)

    assert membership.id is not None
    assert membership.role == MembershipRole.MEMBER
    assert membership.group_id == group.id
    assert membership.user_id == user.id


@pytest.mark.asyncio
async def test_expense_model(session: AsyncSession):
    """Test Expense model creation."""
    user = User(email="payer@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id,
        user_id=user.id,
        role=MembershipRole.OWNER,
    )
    session.add(membership)
    await session.flush()

    expense = Expense(
        group_id=group.id,
        title="Test Expense",
        amount_cents=10000,  # $100.00
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
        memo="Test memo",
    )
    session.add(expense)
    await session.commit()
    await session.refresh(expense)

    assert expense.id is not None
    assert expense.amount_cents == 10000
    assert expense.title == "Test Expense"
    assert expense.version == 1


@pytest.mark.asyncio
async def test_expense_split_model(session: AsyncSession):
    """Test ExpenseSplit model with relationships."""
    user1 = User(email="user1@example.com", password_hash="hash")
    user2 = User(email="user2@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user1, user2, group])
    await session.flush()

    membership1 = Membership(
        group_id=group.id,
        user_id=user1.id,
        role=MembershipRole.MEMBER,
    )
    membership2 = Membership(
        group_id=group.id,
        user_id=user2.id,
        role=MembershipRole.MEMBER,
    )
    session.add_all([membership1, membership2])
    await session.flush()

    expense = Expense(
        group_id=group.id,
        title="Split Expense",
        amount_cents=20000,  # $200.00
        currency="USD",
        paid_by=membership1.id,
        expense_date=date.today(),
    )
    session.add(expense)
    await session.flush()

    split1 = ExpenseSplit(
        expense_id=expense.id,
        group_id=group.id,
        membership_id=membership1.id,
        share_cents=10000,  # $100.00
    )
    split2 = ExpenseSplit(
        expense_id=expense.id,
        group_id=group.id,
        membership_id=membership2.id,
        share_cents=10000,  # $100.00
    )
    session.add_all([split1, split2])
    await session.commit()

    assert split1.share_cents == 10000
    assert split2.share_cents == 10000


@pytest.mark.asyncio
async def test_settlement_batch_model(session: AsyncSession):
    """Test SettlementBatch model."""
    user = User(email="user@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    batch = SettlementBatch(
        group_id=group.id,
        status=SettlementStatus.SUGGESTED,
        total_settlements=2,
    )
    session.add(batch)
    await session.commit()
    await session.refresh(batch)

    assert batch.id is not None
    assert batch.status == SettlementStatus.SUGGESTED
    assert batch.total_settlements == 2
    assert batch.version == 1


@pytest.mark.asyncio
async def test_settlement_model(session: AsyncSession):
    """Test Settlement model."""
    user1 = User(email="user1@example.com", password_hash="hash")
    user2 = User(email="user2@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user1, user2, group])
    await session.flush()

    membership1 = Membership(
        group_id=group.id,
        user_id=user1.id,
        role=MembershipRole.MEMBER,
    )
    membership2 = Membership(
        group_id=group.id,
        user_id=user2.id,
        role=MembershipRole.MEMBER,
    )
    session.add_all([membership1, membership2])
    await session.flush()

    batch = SettlementBatch(
        group_id=group.id,
        status=SettlementStatus.SUGGESTED,
        total_settlements=1,
    )
    session.add(batch)
    await session.flush()

    settlement = Settlement(
        batch_id=batch.id,
        group_id=group.id,
        from_membership=membership1.id,
        to_membership=membership2.id,
        amount_cents=5000,  # $50.00
        status=SettlementStatus.SUGGESTED,
    )
    session.add(settlement)
    await session.commit()
    await session.refresh(settlement)

    assert settlement.id is not None
    assert settlement.amount_cents == 5000
    assert settlement.status == SettlementStatus.SUGGESTED
    assert settlement.from_membership != settlement.to_membership


@pytest.mark.asyncio
async def test_activity_log_model(session: AsyncSession):
    """Test ActivityLog model."""
    user = User(email="user@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id,
        user_id=user.id,
        role=MembershipRole.OWNER,
    )
    session.add(membership)
    await session.flush()

    log = ActivityLog(
        group_id=group.id,
        actor_membership=membership.id,
        event_type="expense.created",
        subject_id=uuid.uuid4(),
        activity_metadata={"key": "value"},
    )
    session.add(log)
    await session.commit()
    await session.refresh(log)

    assert log.id is not None
    assert log.event_type == "expense.created"
    assert log.activity_metadata == {"key": "value"}


@pytest.mark.asyncio
async def test_idempotency_key_model(session: AsyncSession):
    """Test IdempotencyKey model."""
    user = User(email="user@example.com", password_hash="hash")
    session.add(user)
    await session.flush()

    idempotency_key = IdempotencyKey(
        endpoint="/api/expenses",
        user_id=user.id,
        request_hash="abc123",
        response_body={"id": "test-id"},
        status_code=201,
    )
    session.add(idempotency_key)
    await session.commit()
    await session.refresh(idempotency_key)

    assert idempotency_key.id is not None
    assert idempotency_key.endpoint == "/api/expenses"
    assert idempotency_key.request_hash == "abc123"
    assert idempotency_key.status_code == 201


@pytest.mark.asyncio
async def test_group_relationships(session: AsyncSession):
    """Test Group model relationships."""
    user = User(email="user@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id,
        user_id=user.id,
        role=MembershipRole.OWNER,
    )
    session.add(membership)
    await session.flush()

    expense = Expense(
        group_id=group.id,
        title="Test Expense",
        amount_cents=10000,
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
    )
    session.add(expense)
    await session.commit()

    # Test relationships
    await session.refresh(group)
    assert len(group.memberships) == 1
    assert len(group.expenses) == 1
    assert group.memberships[0].id == membership.id
    assert group.expenses[0].id == expense.id


@pytest.mark.asyncio
async def test_expense_relationships(session: AsyncSession):
    """Test Expense model relationships."""
    user = User(email="user@example.com", password_hash="hash")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id,
        user_id=user.id,
        role=MembershipRole.MEMBER,
    )
    session.add(membership)
    await session.flush()

    expense = Expense(
        group_id=group.id,
        title="Test Expense",
        amount_cents=20000,
        currency="USD",
        paid_by=membership.id,
        expense_date=date.today(),
    )
    session.add(expense)
    await session.flush()

    split1 = ExpenseSplit(
        expense_id=expense.id,
        group_id=group.id,
        membership_id=membership.id,
        share_cents=20000,
    )
    session.add(split1)
    await session.commit()

    await session.refresh(expense)
    assert len(expense.splits) == 1
    assert expense.splits[0].share_cents == 20000

