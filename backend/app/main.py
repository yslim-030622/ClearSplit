import logging
from uuid import UUID

from fastapi import Depends, FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import auth, expenses, groups, shopping
from app.api import settlements
from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.membership import Membership
from app.models.user import User
from app.schemas.expense import ExpenseRead, ExpenseSplitRead
from app.services.expense import get_expense_by_id

logger = logging.getLogger(__name__)

app = FastAPI(title="ClearSplit API")


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle validation errors with detailed logging."""
    body = await request.body()
    logger.error(f"Validation error on {request.method} {request.url.path}: {exc.errors()}")
    logger.error(f"Request body: {body.decode('utf-8') if body else 'Empty'}")
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": exc.errors(), "body": body.decode('utf-8') if body else None},
    )

# Include routers
app.include_router(auth.router)
app.include_router(groups.router)
app.include_router(expenses.router)
app.include_router(settlements.router)
app.include_router(shopping.router)


# Separate route for GET /expenses/{expense_id} (not under /groups prefix)
@app.get("/expenses/{expense_id}", response_model=ExpenseRead, tags=["expenses"])
async def get_expense(
    expense_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ExpenseRead:
    """Get a specific expense by ID.

    User must be a member of the expense's group.
    """
    # Get user's all memberships
    result = await session.execute(
        select(Membership).where(Membership.user_id == current_user.id)
    )
    user_memberships = list(result.scalars().all())
    user_membership_ids = {m.id for m in user_memberships}

    expense = await get_expense_by_id(session, expense_id, user_membership_ids)

    expense_response = ExpenseRead.model_validate(expense)
    expense_response.splits = [
        ExpenseSplitRead.model_validate(split) for split in expense.splits
    ]

    return expense_response


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
