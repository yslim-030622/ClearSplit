"""Expense service layer for business logic."""

import hashlib
import json
from datetime import date
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.expense import Expense
from app.models.expense_split import ExpenseSplit
from app.models.membership import Membership


def calculate_equal_splits(amount_cents: int, num_splits: int) -> list[int]:
    """Calculate equal splits with remainder distribution.

    Args:
        amount_cents: Total amount in cents
        num_splits: Number of people to split among

    Returns:
        List of share amounts in cents for each person

    Example:
        amount_cents=1000, num_splits=3
        Returns: [334, 333, 333] (first person gets remainder)
    """
    if num_splits <= 0:
        raise ValueError("Number of splits must be positive")

    base_share = amount_cents // num_splits
    remainder = amount_cents % num_splits

    # First 'remainder' people get base_share + 1, rest get base_share
    splits = [base_share + 1] * remainder + [base_share] * (num_splits - remainder)
    return splits


async def validate_memberships_in_group(
    session: AsyncSession, group_id: UUID, membership_ids: list[UUID]
) -> list[Membership]:
    """Validate that all membership IDs belong to the group.

    Args:
        session: Database session
        group_id: Group UUID
        membership_ids: List of membership UUIDs to validate

    Returns:
        List of validated memberships

    Raises:
        HTTPException: If any membership is not found or not in group
    """
    result = await session.execute(
        select(Membership).where(
            Membership.id.in_(membership_ids), Membership.group_id == group_id
        )
    )
    memberships = list(result.scalars().all())

    if len(memberships) != len(membership_ids):
        found_ids = {m.id for m in memberships}
        missing_ids = set(membership_ids) - found_ids
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Memberships not found in group: {missing_ids}",
        )

    return memberships


async def create_expense_with_equal_splits(
    session: AsyncSession,
    group_id: UUID,
    title: str,
    amount_cents: int,
    currency: str,
    paid_by_membership_id: UUID,
    expense_date: date,
    split_among_membership_ids: list[UUID],
    memo: str | None = None,
) -> Expense:
    """Create an expense with equal splits.

    This is an atomic operation: both expense and splits are created
    in a single transaction.

    Args:
        session: Database session
        group_id: Group UUID
        title: Expense title
        amount_cents: Expense amount in cents
        currency: Currency code
        paid_by_membership_id: Membership ID of payer
        expense_date: Date of expense
        split_among_membership_ids: List of membership IDs to split among
        memo: Optional memo

    Returns:
        Created expense

    Raises:
        HTTPException: If validations fail
    """
    # Validate payer is in group
    payer_result = await session.execute(
        select(Membership).where(
            Membership.id == paid_by_membership_id, Membership.group_id == group_id
        )
    )
    payer = payer_result.scalar_one_or_none()
    if not payer:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Payer membership not found in group",
        )

    # Validate all split memberships are in group
    await validate_memberships_in_group(session, group_id, split_among_membership_ids)

    # Calculate equal splits
    num_splits = len(split_among_membership_ids)
    share_amounts = calculate_equal_splits(amount_cents, num_splits)

    # Create expense
    expense = Expense(
        group_id=group_id,
        title=title,
        amount_cents=amount_cents,
        currency=currency,
        paid_by=paid_by_membership_id,
        expense_date=expense_date,
        memo=memo,
    )
    session.add(expense)
    await session.flush()

    # Create splits
    splits = []
    for membership_id, share_cents in zip(split_among_membership_ids, share_amounts):
        split = ExpenseSplit(
            expense_id=expense.id,
            group_id=group_id,
            membership_id=membership_id,
            share_cents=share_cents,
        )
        splits.append(split)
        session.add(split)

    await session.commit()
    await session.refresh(expense, attribute_names=["splits"])

    return expense


async def get_expense_by_id(
    session: AsyncSession, expense_id: UUID, user_membership_ids: set[UUID]
) -> Expense:
    """Get expense by ID, ensuring user is a member of the group.

    Args:
        session: Database session
        expense_id: Expense UUID
        user_membership_ids: Set of membership IDs for the user

    Returns:
        Expense

    Raises:
        HTTPException: If expense not found or user is not a member
    """
    result = await session.execute(
        select(Expense)
        .options(selectinload(Expense.splits))
        .where(Expense.id == expense_id)
    )
    expense = result.scalar_one_or_none()

    if not expense:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Expense not found",
        )

    # Check if user is a member of the group
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == expense.group_id,
            Membership.id.in_(user_membership_ids),
        )
    )
    membership = result.scalar_one_or_none()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this expense's group",
        )

    return expense


async def get_group_expenses(
    session: AsyncSession, group_id: UUID, user_membership_ids: set[UUID]
) -> list[Expense]:
    """Get all expenses for a group.

    Args:
        session: Database session
        group_id: Group UUID
        user_membership_ids: Set of membership IDs for the user

    Returns:
        List of expenses

    Raises:
        HTTPException: If user is not a member
    """
    # Verify user is a member
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id, Membership.id.in_(user_membership_ids)
        )
    )
    membership = result.scalar_one_or_none()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    # Get expenses
    result = await session.execute(
        select(Expense)
        .options(selectinload(Expense.splits))
        .where(Expense.group_id == group_id)
        .order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    )
    return list(result.scalars().all())


def compute_request_hash(request_body: dict) -> str:
    """Compute hash of request body for idempotency.
    
    Handles non-JSON-serializable types (date, datetime, UUID, Enum, Decimal)
    by normalizing them before hashing.

    Args:
        request_body: Request body as dict

    Returns:
        SHA256 hash as hex string
    """
    from fastapi.encoders import jsonable_encoder
    
    # Normalize to JSON-serializable types
    # date -> "YYYY-MM-DD", UUID -> str, Enum -> value, etc.
    normalized = jsonable_encoder(request_body)
    
    # Sort keys for consistent hashing, compact format
    sorted_json = json.dumps(normalized, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(sorted_json.encode("utf-8")).hexdigest()
