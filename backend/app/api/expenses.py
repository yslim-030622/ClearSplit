"""Expenses API routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.core.idempotency import (
    get_idempotency_key_from_header,
    get_or_create_idempotency_key,
    store_idempotency_response,
)
from app.db.session import get_session
from app.models.expense import Expense
from app.models.membership import Membership
from app.models.user import User
from app.schemas.expense import ExpenseCreateEqualSplit, ExpenseRead, ExpenseSplitRead
from app.services.expense import (
    create_expense_with_equal_splits,
    get_expense_by_id,
    get_group_expenses,
)

router = APIRouter(prefix="/groups", tags=["expenses"])


@router.post(
    "/{group_id}/expenses",
    response_model=ExpenseRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_expense(
    group_id: UUID,
    request: ExpenseCreateEqualSplit,
    http_request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExpenseRead:
    """Create a new expense with equal splits.

    Supports idempotency via Idempotency-Key header.
    If the same request is made twice with the same key, the second
    request returns the same response without creating a duplicate.

    Args:
        group_id: Group UUID
        request: Expense creation request
        http_request: FastAPI request (for idempotency key)
        current_user: Current authenticated user
        session: Database session

    Returns:
        Created expense

    Raises:
        HTTPException: If validations fail
    """
    # Get user's memberships in this group
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id, Membership.user_id == current_user.id
        )
    )
    user_membership = result.scalar_one_or_none()
    if not user_membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    # Check idempotency
    idempotency_key_header = get_idempotency_key_from_header(http_request)
    if idempotency_key_header:
        request_body = request.model_dump()
        existing_key = await get_or_create_idempotency_key(
            session,
            endpoint=f"POST /groups/{group_id}/expenses",
            user_id=current_user.id,
            request_body=request_body,
        )

        if existing_key and existing_key.response_body:
            # Return cached response
            return ExpenseRead.model_validate(existing_key.response_body)

    # Create expense
    expense = await create_expense_with_equal_splits(
        session,
        group_id=group_id,
        title=request.title,
        amount_cents=request.amount_cents,
        currency=request.currency,
        paid_by_membership_id=request.paid_by,
        expense_date=request.expense_date,
        split_among_membership_ids=request.split_among,
        memo=request.memo,
    )

    # Load splits for response
    await session.refresh(expense)
    expense_response = ExpenseRead.model_validate(expense)
    expense_response.splits = [
        ExpenseSplitRead.model_validate(split) for split in expense.splits
    ]

    # Store idempotency key if provided
    if idempotency_key_header:
        await store_idempotency_response(
            session,
            endpoint=f"POST /groups/{group_id}/expenses",
            user_id=current_user.id,
            request_body=request.model_dump(),
            response_body=expense_response.model_dump(),
            status_code=201,
        )

    return expense_response


@router.get("/{group_id}/expenses", response_model=list[ExpenseRead])
async def list_group_expenses(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[ExpenseRead]:
    """List all expenses for a group.

    Args:
        group_id: Group UUID
        current_user: Current authenticated user
        session: Database session

    Returns:
        List of expenses

    Raises:
        HTTPException: If user is not a member
    """
    # Get user's membership IDs in this group
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id, Membership.user_id == current_user.id
        )
    )
    user_memberships = list(result.scalars().all())
    if not user_memberships:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    user_membership_ids = {m.id for m in user_memberships}
    expenses = await get_group_expenses(session, group_id, user_membership_ids)

    expense_responses = []
    for expense in expenses:
        expense_response = ExpenseRead.model_validate(expense)
        expense_response.splits = [
            ExpenseSplitRead.model_validate(split) for split in expense.splits
        ]
        expense_responses.append(expense_response)

    return expense_responses

