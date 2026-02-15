import logging
from contextlib import asynccontextmanager
from urllib.parse import urlparse
from uuid import UUID

from fastapi import Depends, FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import text

from app.api import auth, expenses, friends, groups, shopping
from app.api import settlements
from app.auth.dependencies import get_current_user
from app.core.config import get_settings
from app.db.session import engine, get_session
from app.models.membership import Membership
from app.models.user import User
from app.schemas.expense import ExpenseRead, ExpenseSplitRead
from app.services.expense import get_expense_by_id

logger = logging.getLogger(__name__)

# CORS middleware for iOS app
settings = get_settings()
env_name = settings.env.lower()


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield
    await engine.dispose()


app = FastAPI(
    title="ClearSplit API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if env_name in {"local", "test"} else None,
    redoc_url="/redoc" if env_name in {"local", "test"} else None,
    openapi_url="/openapi.json" if env_name in {"local", "test"} else None,
)

local_origins = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]


def _validate_non_local_cors_origins(origins: list[str]) -> None:
    invalid: list[str] = []
    for origin in origins:
        parsed = urlparse(origin)
        has_invalid_path_bits = any([parsed.path not in {"", "/"}, parsed.params, parsed.query, parsed.fragment])
        is_https_origin = parsed.scheme == "https" and bool(parsed.netloc)
        if not is_https_origin or has_invalid_path_bits:
            invalid.append(origin)

    if invalid:
        invalid_values = ", ".join(invalid)
        raise RuntimeError(
            "Invalid CORS_ORIGINS value(s) for non-local environment: "
            f"{invalid_values}. Use comma-separated HTTPS origins only "
            "(e.g. https://app.example.com)."
        )


if env_name in {"local", "test"}:
    cors_origins = sorted(set(local_origins + settings.get_cors_origins()))
    allow_credentials = False
else:
    cors_origins = settings.get_cors_origins()
    if not cors_origins:
        raise RuntimeError(
            "CORS_ORIGINS must be configured in non-local environments. "
            "Use a comma-separated list of trusted https origins."
        )
    _validate_non_local_cors_origins(cors_origins)
    allow_credentials = True

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle validation errors without logging or returning sensitive request payloads."""
    error_paths = ["/".join(str(part) for part in err.get("loc", [])) for err in exc.errors()]
    logger.warning(
        "Validation error on %s %s for fields=%s",
        request.method,
        request.url.path,
        error_paths,
    )
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": exc.errors()},
    )

# Include routers
app.include_router(auth.router)
app.include_router(friends.router)
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


async def _build_health_payload(db: AsyncSession) -> tuple[dict[str, str | bool], int]:
    response: dict[str, str | bool] = {
        "status": "ok",
        "database": False,
        "s3": False,
    }
    status_code = status.HTTP_200_OK

    # Check database connection
    try:
        await db.execute(text("SELECT 1"))
        response["database"] = True
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        response["status"] = "degraded"
        status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    # Check S3 configuration (lightweight availability signal)
    response["s3"] = bool(settings.s3_bucket_name)
    return response, status_code


@app.get("/health/live")
async def health_live() -> dict[str, str]:
    """Liveness probe endpoint that validates process availability."""
    return {"status": "ok"}


@app.get("/health/ready")
async def health_ready(db: AsyncSession = Depends(get_session)) -> JSONResponse:
    """Readiness probe endpoint that validates dependency availability."""
    detailed = env_name in {"local", "test"}
    response, status_code = await _build_health_payload(db)

    if detailed:
        return JSONResponse(content=response, status_code=status_code)
    return JSONResponse(
        content={"status": str(response["status"])},
        status_code=status_code,
    )


@app.get("/health")
async def health(db: AsyncSession = Depends(get_session)) -> JSONResponse:
    """Backwards-compatible health alias that maps to readiness checks."""
    return await health_ready(db)
