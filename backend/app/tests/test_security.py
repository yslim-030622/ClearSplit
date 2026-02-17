"""Security-focused regression tests."""

from __future__ import annotations

import base64
import importlib
import json
from datetime import datetime, timedelta, timezone

import jwt
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import auth as auth_api
from app.auth.jwt import create_access_token, create_refresh_token
from app.core.config import get_settings
from app.tests.conftest import create_test_user


@pytest_asyncio.fixture
async def production_client(monkeypatch: pytest.MonkeyPatch) -> AsyncClient:
    """Create an isolated app instance configured as production."""
    monkeypatch.setenv("ENV", "production")
    monkeypatch.setenv("CORS_ORIGINS", "https://app.example.com")

    get_settings.cache_clear()
    import app.main as app_main

    prod_main = importlib.reload(app_main)
    app = prod_main.app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client

    # Keep global settings cache clean for the rest of the test suite.
    get_settings.cache_clear()


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/health/live", "/auth/me"])
async def test_security_headers_present_on_responses(client: AsyncClient, path: str):
    response = await client.get(path)

    # /auth/me is protected and may return 401/403 in no-token scenarios.
    assert response.status_code in {200, 401, 403}
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
    assert response.headers["X-Permitted-Cross-Domain-Policies"] == "none"
    assert "Strict-Transport-Security" not in response.headers


@pytest.mark.asyncio
async def test_security_headers_include_hsts_in_non_local_env(production_client: AsyncClient):
    response = await production_client.get("/health/live")

    assert response.status_code == 200
    assert response.headers["Strict-Transport-Security"] == "max-age=63072000; includeSubDomains"


@pytest.mark.asyncio
async def test_cors_rejects_disallowed_origin(client: AsyncClient):
    response = await client.options(
        "/auth/login",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "POST",
        },
    )

    # Starlette CORS middleware returns 400 for disallowed preflight origins.
    assert response.status_code in {400, 403}
    assert "access-control-allow-origin" not in {
        key.lower(): value for key, value in response.headers.items()
    }


@pytest.mark.asyncio
async def test_auth_bypass_missing_token_blocked(client: AsyncClient):
    response = await client.get("/auth/me")
    assert response.status_code in {401, 403}


@pytest.mark.asyncio
async def test_auth_bypass_malformed_token_blocked(client: AsyncClient):
    response = await client.get(
        "/auth/me",
        headers={"Authorization": "Bearer not-a-valid-jwt"},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_auth_bypass_wrong_token_type_blocked(
    client: AsyncClient, session: AsyncSession
):
    user = create_test_user(email="security-refresh@example.com", username="security_refresh")
    session.add(user)
    await session.flush()

    refresh_token = create_refresh_token(user.id, user.email)
    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {refresh_token}"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_auth_bypass_expired_token_blocked(client: AsyncClient, session: AsyncSession):
    settings = get_settings()
    user = create_test_user(email="security-expired@example.com", username="security_expired")
    session.add(user)
    await session.flush()

    expired_access = jwt.encode(
        {
            "sub": str(user.id),
            "email": user.email,
            "type": "access",
            "exp": datetime.now(tz=timezone.utc) - timedelta(minutes=1),
        },
        settings.get_jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )

    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {expired_access}"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_token_tampering_modified_payload_rejected(
    client: AsyncClient, session: AsyncSession
):
    user = create_test_user(email="security-tamper@example.com", username="security_tamper")
    session.add(user)
    await session.flush()

    token = create_access_token(user.id, user.email)
    header, payload, signature = token.split(".")

    payload_json = json.loads(_b64url_decode(payload).decode("utf-8"))
    payload_json["email"] = "attacker@example.com"
    tampered_payload = _b64url_encode(json.dumps(payload_json, separators=(",", ":")).encode("utf-8"))
    tampered = f"{header}.{tampered_payload}.{signature}"

    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {tampered}"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_token_with_empty_subject_rejected(client: AsyncClient):
    settings = get_settings()
    token = jwt.encode(
        {
            "sub": "",
            "email": "security-empty-sub@example.com",
            "type": "access",
            "exp": datetime.now(tz=timezone.utc) + timedelta(minutes=5),
        },
        settings.get_jwt_secret(),
        algorithm=settings.jwt_algorithm,
    )

    response = await client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 401


@pytest.mark.asyncio
async def test_login_runs_password_verification_for_unknown_user(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    user = create_test_user(email="timing@example.com", username="timing_user")
    session.add(user)
    await session.flush()

    seen_hashes: list[str] = []

    def fake_verify(password: str, password_hash: str) -> bool:
        seen_hashes.append(password_hash)
        return False

    monkeypatch.setattr(auth_api, "verify_password", fake_verify)

    missing_user = await client.post(
        "/auth/login",
        json={"identifier": "unknown@example.com", "password": "password123"},
    )
    existing_user = await client.post(
        "/auth/login",
        json={"identifier": "timing@example.com", "password": "wrong-password"},
    )

    assert missing_user.status_code == 401
    assert existing_user.status_code == 401
    assert len(seen_hashes) == 2
    assert seen_hashes[0] == auth_api._DUMMY_PASSWORD_HASH
    assert seen_hashes[1] == user.password_hash


@pytest.mark.asyncio
async def test_oversized_payload_is_rejected(client: AsyncClient):
    response = await client.post(
        "/auth/signup",
        json={
            "username": "x" * 5000,
            "email": "oversized@example.com",
            "password": "password123",
            "first_name": "Over",
            "last_name": "Sized",
        },
    )

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_path_traversal_like_identifier_is_rejected(
    client: AsyncClient, session: AsyncSession
):
    user = create_test_user(email="path-user@example.com", username="path_user")
    session.add(user)
    await session.flush()
    access_token = create_access_token(user.id, user.email)

    invalid_uuid = await client.get(
        "/groups/not-a-uuid",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    traversal_like = await client.get(
        "/groups/%2e%2e%2fetc%2fpasswd",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert invalid_uuid.status_code == 422
    assert traversal_like.status_code in {404, 422}


@pytest.mark.asyncio
async def test_validation_error_response_does_not_echo_raw_input(client: AsyncClient):
    sensitive_password = "S3cret!"
    response = await client.post(
        "/auth/signup",
        json={
            "username": "secure-user",
            "email": "security-validation@example.com",
            "password": sensitive_password,
            "first_name": "Sec",
            "last_name": "Validation",
        },
    )

    assert response.status_code == 422
    body = response.json()
    assert sensitive_password not in response.text
    assert "detail" in body
    assert all("input" not in err for err in body["detail"])


@pytest.mark.asyncio
async def test_health_endpoints_are_public(client: AsyncClient):
    live = await client.get("/health/live")
    ready = await client.get("/health/ready")

    assert live.status_code == 200
    assert live.json() == {"status": "ok"}

    assert ready.status_code in {200, 503}
    ready_payload = ready.json()
    assert "status" in ready_payload
    assert "database_url" not in ready_payload
    assert "jwt_secret" not in ready_payload


@pytest.mark.asyncio
async def test_health_ready_is_sanitized_in_non_local_env(production_client: AsyncClient):
    response = await production_client.get("/health/ready")

    assert response.status_code in {200, 503}
    payload = response.json()
    assert list(payload.keys()) == ["status"]


@pytest.mark.asyncio
async def test_docs_are_disabled_in_non_local_env(production_client: AsyncClient):
    docs = await production_client.get("/docs")
    redoc = await production_client.get("/redoc")
    openapi = await production_client.get("/openapi.json")

    assert docs.status_code == 404
    assert redoc.status_code == 404
    assert openapi.status_code == 404


def _b64url_decode(value: str) -> bytes:
    padded = value + "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(padded.encode("utf-8"))


def _b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("utf-8")
