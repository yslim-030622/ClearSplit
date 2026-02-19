"""Tests for authentication endpoints."""

from uuid import uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token, decode_token
from app.core import rate_limit as rate_limit_module
from app.models.user import User
from app.tests.conftest import create_test_user


@pytest.mark.asyncio
async def test_signup_success(client: AsyncClient, session: AsyncSession):
    """Test successful user signup."""
    response = await client.post(
        "/auth/signup",
        json={
            "username": "testuser",
            "email": "test@example.com",
            "password": "password123",
            "first_name": "Test",
            "last_name": "User",
        },
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
    user = create_test_user(email="existing@example.com", username="existing")
    session.add(user)
    await session.commit()

    # Try to signup with same email
    response = await client.post(
        "/auth/signup",
        json={
            "username": "existing2",
            "email": "existing@example.com",
            "password": "password123",
            "first_name": "Test",
            "last_name": "User",
        },
    )

    assert response.status_code == 400
    assert "already registered" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_signup_duplicate_email_case_insensitive(client: AsyncClient, session: AsyncSession):
    """Signup should reject duplicate emails regardless of legacy casing."""
    unique_suffix = uuid4().hex[:8]
    normalized_email = f"admin-{unique_suffix}@example.com"
    user = create_test_user(
        email=f"Admin-{unique_suffix}@example.com",
        username=f"admin-{unique_suffix}",
    )
    session.add(user)
    await session.commit()

    response = await client.post(
        "/auth/signup",
        json={
            "username": f"admin2-{unique_suffix}",
            "email": normalized_email,
            "password": "password123",
            "first_name": "Admin",
            "last_name": "User",
        },
    )

    assert response.status_code == 400
    assert "already registered" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_login_success(client: AsyncClient, session: AsyncSession):
    """Test successful login."""
    # Create user
    user = create_test_user(email="login@example.com", username="loginuser")
    session.add(user)
    await session.commit()

    # Login
    response = await client.post(
        "/auth/login",
        json={"identifier": "login@example.com", "password": "password123"},
    )

    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "login@example.com"


@pytest.mark.asyncio
async def test_login_legacy_case_insensitive_identifier(client: AsyncClient, session: AsyncSession):
    """Login should still work for legacy mixed-case username/email rows."""
    unique_suffix = uuid4().hex[:8]
    normalized_email = f"admin-{unique_suffix}@example.com"
    user = create_test_user(
        email=f"Admin-{unique_suffix}@example.com",
        username=f"AdminUser-{unique_suffix}",
    )
    session.add(user)
    await session.commit()

    response = await client.post(
        "/auth/login",
        json={"identifier": normalized_email, "password": "password123"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["user"]["email"].lower() == normalized_email


@pytest.mark.asyncio
async def test_login_invalid_email(client: AsyncClient):
    """Test login with invalid email."""
    response = await client.post(
        "/auth/login",
        json={"identifier": "nonexistent@example.com", "password": "password123"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_login_invalid_password(client: AsyncClient, session: AsyncSession):
    """Test login with invalid password."""
    # Create user
    user = create_test_user(email="wrongpass@example.com", password="correctpass", username="wrongpass")
    session.add(user)
    await session.commit()

    # Try to login with wrong password
    response = await client.post(
        "/auth/login",
        json={"identifier": "wrongpass@example.com", "password": "wrongpassword"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_refresh_token_success(client: AsyncClient, session: AsyncSession):
    """Test successful token refresh."""
    # Create user
    user = create_test_user(email="refresh@example.com", username="refreshuser")
    session.add(user)
    await session.commit()

    login_response = await client.post(
        "/auth/login",
        json={"identifier": "refresh@example.com", "password": "password123"},
    )
    assert login_response.status_code == 200
    refresh_token = login_response.json()["refresh_token"]

    # Refresh access token
    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"

    # Verify new access token is valid
    new_access_token = data["access_token"]
    payload = decode_token(new_access_token, token_type="access")
    assert payload["sub"] == str(user.id)
    assert payload["type"] == "access"


@pytest.mark.asyncio
async def test_refresh_token_rate_limit_enforced(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    """Refresh endpoint should enforce abuse throttling."""
    user = create_test_user(email="refresh-rate-limit@example.com", username="refreshratelimit")
    session.add(user)
    await session.commit()

    login_response = await client.post(
        "/auth/login",
        json={"identifier": "refresh-rate-limit@example.com", "password": "password123"},
    )
    assert login_response.status_code == 200
    refresh_token = login_response.json()["refresh_token"]

    monkeypatch.setattr(rate_limit_module, "_rate_limit_enabled", True)
    monkeypatch.setattr(rate_limit_module._refresh_limiter, "limit", 1)
    rate_limit_module._refresh_limiter._events.clear()
    rate_limit_module._refresh_limiter._last_seen.clear()

    first_response = await client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    second_response = await client.post(
        "/auth/refresh",
        json={"refresh_token": refresh_token},
    )

    assert first_response.status_code == 200
    assert second_response.status_code == 429
    assert "too many token refresh attempts" in second_response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_refresh_token_replay_is_blocked(client: AsyncClient, session: AsyncSession):
    """Old refresh token should stop working right after rotation."""
    user = create_test_user(email="rotate@example.com", username="rotateuser")
    session.add(user)
    await session.commit()

    login_response = await client.post(
        "/auth/login",
        json={"identifier": "rotate@example.com", "password": "password123"},
    )
    assert login_response.status_code == 200
    original_refresh = login_response.json()["refresh_token"]

    first_refresh = await client.post(
        "/auth/refresh",
        json={"refresh_token": original_refresh},
    )
    assert first_refresh.status_code == 200
    rotated_refresh = first_refresh.json()["refresh_token"]

    replay_attempt = await client.post(
        "/auth/refresh",
        json={"refresh_token": original_refresh},
    )
    assert replay_attempt.status_code == 401

    second_refresh = await client.post(
        "/auth/refresh",
        json={"refresh_token": rotated_refresh},
    )
    assert second_refresh.status_code == 200


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
async def test_refresh_token_with_non_uuid_subject_returns_401(client: AsyncClient):
    """Malformed refresh token subject should be rejected as unauthorized."""
    from datetime import datetime, timedelta, timezone

    import jwt

    from app.core.config import get_settings

    settings = get_settings()
    malformed_refresh = jwt.encode(
        {
            "sub": "not-a-uuid",
            "email": "malformed@example.com",
            "type": "refresh",
            "jti": "malformed-jti",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        settings.get_jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )

    response = await client.post(
        "/auth/refresh",
        json={"refresh_token": malformed_refresh},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_get_me_success(client: AsyncClient, session: AsyncSession):
    """Test getting current user info."""
    # Create user
    user = create_test_user(email="me@example.com", username="meuser")
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
async def test_get_me_with_non_uuid_subject_returns_401(client: AsyncClient):
    """Malformed access token subject should never bubble as a server error."""
    from datetime import datetime, timedelta, timezone

    import jwt

    from app.core.config import get_settings

    settings = get_settings()
    malformed_access = jwt.encode(
        {
            "sub": "not-a-uuid",
            "email": "malformed@example.com",
            "type": "access",
            "exp": datetime.now(timezone.utc) + timedelta(minutes=5),
        },
        settings.get_jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )

    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {malformed_access}"},
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_get_me_no_token(client: AsyncClient):
    """Test getting current user without token."""
    response = await client.get("/auth/me")

    assert response.status_code in {401, 403}


@pytest.mark.asyncio
async def test_expired_token(client: AsyncClient, session: AsyncSession):
    """Test access with expired token."""
    from datetime import datetime, timedelta, timezone

    import jwt

    from app.core.config import get_settings

    settings = get_settings()

    # Create user
    user = create_test_user(email="expired@example.com", username="expireduser")
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
        settings.get_jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )

    # Try to use expired token
    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {expired_token}"},
    )

    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower() or "invalid" in response.json()["detail"].lower()
