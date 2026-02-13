"""Authentication API routes."""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.auth.jwt import (
    BEARER_TOKEN_TYPE,
    JWTError,
    create_access_token,
    create_refresh_token_with_claims,
    get_refresh_token_identity,
)
from app.auth.password import hash_password, verify_password
from app.auth.refresh_tokens import (
    persist_refresh_token,
    validate_and_rotate_refresh_token,
)
from app.core.rate_limit import enforce_login_rate_limit, enforce_signup_rate_limit
from app.db.session import get_session
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    RefreshTokenRequest,
    RefreshTokenResponse,
    SignupRequest,
    TokenResponse,
)
from app.schemas.user import UserRead

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def signup(
    request: SignupRequest,
    http_request: Request,
    session: AsyncSession = Depends(get_session),
) -> TokenResponse:
    """Create a new user account.

    Args:
        request: Signup request with username, email, password, first_name, last_name
        session: Database session

    Returns:
        Token response with access token, refresh token, and user info

    Raises:
        HTTPException: If username or email already exists
    """
    await enforce_signup_rate_limit(http_request)

    logger.info(f"Signup attempt for username: {request.username}, email: {request.email}")
    
    # Check if username already exists (check first for better error message)
    result = await session.execute(select(User).where(User.username == request.username))
    existing_user_by_username = result.scalar_one_or_none()

    if existing_user_by_username:
        logger.warning(f"Signup failed: Username '{request.username}' already taken")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already taken",
        )

    # Check if email already exists
    result = await session.execute(select(User).where(User.email == request.email))
    existing_user_by_email = result.scalar_one_or_none()

    if existing_user_by_email:
        logger.warning(f"Signup failed: Email '{request.email}' already registered")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    # Create new user
    try:
        password_hash = hash_password(request.password)
        user = User(
            username=request.username,
            email=request.email,
            password_hash=password_hash,
            first_name=request.first_name,
            last_name=request.last_name,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        logger.info(f"User created successfully: {user.id} ({user.username})")
    except Exception as e:
        logger.error(f"Error creating user: {e}", exc_info=True)
        await session.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create user account",
        )

    # Generate tokens
    access_token = create_access_token(user.id, user.email)
    refresh_bundle = create_refresh_token_with_claims(user.id, user.email)
    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti=refresh_bundle["jti"],
        expires_at=refresh_bundle["expires_at"],
    )
    await session.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_bundle["token"],
        token_type=BEARER_TOKEN_TYPE,
        user=UserRead.model_validate(user),
    )


@router.post("/login", response_model=TokenResponse)
async def login(
    request: LoginRequest,
    http_request: Request,
    session: AsyncSession = Depends(get_session),
) -> TokenResponse:
    """Authenticate user and return tokens.

    Args:
        request: Login request with username/email identifier and password
        session: Database session

    Returns:
        Token response with access token, refresh token, and user info

    Raises:
        HTTPException: If username/email or password is invalid
    """
    await enforce_login_rate_limit(http_request)

    # Find user by username or email (try both)
    result = await session.execute(
        select(User).where(
            or_(User.username == request.identifier, User.email == request.identifier)
        )
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username/email or password",
        )

    # Verify password
    if not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username/email or password",
        )

    # Generate tokens
    access_token = create_access_token(user.id, user.email)
    refresh_bundle = create_refresh_token_with_claims(user.id, user.email)
    await persist_refresh_token(
        session,
        user_id=user.id,
        token_jti=refresh_bundle["jti"],
        expires_at=refresh_bundle["expires_at"],
    )
    await session.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_bundle["token"],
        token_type=BEARER_TOKEN_TYPE,
        user=UserRead.model_validate(user),
    )


@router.post("/refresh", response_model=RefreshTokenResponse)
async def refresh(
    request: RefreshTokenRequest,
    session: AsyncSession = Depends(get_session),
) -> RefreshTokenResponse:
    """Refresh access token using refresh token.

    Args:
        request: Refresh token request
        session: Database session

    Returns:
        New access token

    Raises:
        HTTPException: If refresh token is invalid or expired
    """
    try:
        user_id, current_jti = get_refresh_token_identity(request.refresh_token)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    # Verify user still exists
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    new_refresh_bundle = create_refresh_token_with_claims(user.id, user.email)
    await validate_and_rotate_refresh_token(
        session,
        user_id=user.id,
        current_jti=current_jti,
        replacement_jti=new_refresh_bundle["jti"],
        replacement_expires_at=new_refresh_bundle["expires_at"],
    )

    # Issue a fresh access token only after refresh token rotation succeeds.
    access_token = create_access_token(user.id, user.email)
    await session.commit()

    return RefreshTokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_bundle["token"],
        token_type=BEARER_TOKEN_TYPE,
    )


@router.get("/me", response_model=UserRead)
async def get_me(
    current_user: User = Depends(get_current_user),
) -> UserRead:
    """Get current authenticated user information.

    Args:
        current_user: Current authenticated user from dependency

    Returns:
        User information
    """
    return UserRead.model_validate(current_user)
