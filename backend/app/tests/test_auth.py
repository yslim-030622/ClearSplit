"""Tests for authentication endpoints."""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token, create_refresh_token, decode_token
from app.auth.password import hash_password
from app.main import app
from app.models.user import User


@pytest.mark.asyncio
async def test_signup_success(client: AsyncClient, session: AsyncSession):
    """Test successful user signup."""
    response = await client.post(
        "/auth/signup",
        json={"email": "test@example.com", "password": "password123"},
    )

    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "test@example.com"
    assert "id" in data["user"]

    # Verify user was created in database
    from sqlalchemy import select

    result = await session.execute(select(User).where(User.email == "test@example.com"))
    user = result.scalar_one_or_none()
    assert user is not None
    assert user.email == "test@example.com"


@pytest.mark.asyncio
async def test_signup_duplicate_email(client: AsyncClient, session: AsyncSession):
    """Test signup with duplicate email."""
    # Create existing user
    user = User(email="existing@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Try to signup with same email
    response = await client.post(
        "/auth/signup",
        json={"email": "existing@example.com", "password": "password123"},
    )

    assert response.status_code == 400
    assert "already registered" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_login_success(client: AsyncClient, session: AsyncSession):
    """Test successful login."""
    # Create user
    user = User(email="login@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Login
    response = await client.post(
        "/auth/login",
        json={"email": "login@example.com", "password": "password123"},
    )

    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "login@example.com"


@pytest.mark.asyncio
async def test_login_invalid_email(client: AsyncClient):
    """Test login with invalid email."""
    response = await client.post(
        "/auth/login",
        json={"email": "nonexistent@example.com", "password": "password123"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_login_invalid_password(client: AsyncClient, session: AsyncSession):
    """Test login with invalid password."""
    # Create user
    user = User(email="wrongpass@example.com", password_hash=hash_password("correctpass"))
    session.add(user)
    await session.commit()

    # Try to login with wrong password
    response = await client.post(
        "/auth/login",
        json={"email": "wrongpass@example.com", "password": "wrongpassword"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_refresh_token_success(client: AsyncClient, session: AsyncSession):
    """Test successful token refresh."""
    # Create user
    user = User(email="refresh@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Get refresh token
    refresh_token = create_refresh_token(user.id, user.email)

    # Refresh access token
    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"

    # Verify new access token is valid
    new_access_token = data["access_token"]
    payload = decode_token(new_access_token, token_type="access")
    assert payload["sub"] == str(user.id)
    assert payload["type"] == "access"


@pytest.mark.asyncio
async def test_refresh_token_invalid(client: AsyncClient):
    """Test refresh with invalid token."""
    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": "invalid_token"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower() or "expired" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_get_me_success(client: AsyncClient, session: AsyncSession):
    """Test getting current user info."""
    # Create user
    user = User(email="me@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Get current user
    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "me@example.com"
    assert data["id"] == str(user.id)


@pytest.mark.asyncio
async def test_get_me_invalid_token(client: AsyncClient):
    """Test getting current user with invalid token."""
    response = await client.get(
        "/auth/me",
        headers={"Authorization": "Bearer invalid_token"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_get_me_no_token(client: AsyncClient):
    """Test getting current user without token."""
    response = await client.get("/auth/me")

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_expired_token(client: AsyncClient, session: AsyncSession):
    """Test access with expired token."""
    from datetime import datetime, timedelta, timezone

    from jose import jwt

    from app.core.config import get_settings

    settings = get_settings()

    # Create user
    user = User(email="expired@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

    # Create expired token
    expire = datetime.now(timezone.utc) - timedelta(minutes=1)  # Expired 1 minute ago
    expired_token = jwt.encode(
        {
            "sub": str(user.id),
            "email": user.email,
            "type": "access",
            "exp": expire,
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )

    # Try to use expired token
    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {expired_token}"},
    )

    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower() or "invalid" in response.json()["detail"].lower()

