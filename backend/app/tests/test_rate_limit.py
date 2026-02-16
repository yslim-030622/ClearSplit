"""Isolated tests for in-memory rate limiter behavior."""

import ipaddress

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.core import rate_limit as rate_limit_module
from app.core.rate_limit import InMemoryRateLimiter, _client_identifier


@pytest.mark.asyncio
async def test_inmemory_rate_limiter_enforces_limit_and_recovers_after_window():
    monotonic_values = iter((10.0, 10.2, 10.4, 11.5))
    limiter = InMemoryRateLimiter(
        limit=2,
        window_seconds=1,
        max_keys=1000,
        now_fn=lambda: next(monotonic_values),
    )

    await limiter.enforce("login:client-a", detail="Too many login attempts.")
    await limiter.enforce("login:client-a", detail="Too many login attempts.")

    with pytest.raises(HTTPException) as exc_info:
        await limiter.enforce("login:client-a", detail="Too many login attempts.")
    assert exc_info.value.status_code == 429
    assert "too many login attempts" in exc_info.value.detail.lower()

    await limiter.enforce("login:client-a", detail="Too many login attempts.")


@pytest.mark.asyncio
async def test_inmemory_rate_limiter_tracks_clients_independently():
    limiter = InMemoryRateLimiter(limit=1, window_seconds=60, max_keys=1000)

    await limiter.enforce("signup:client-a", detail="Too many signup attempts.")
    await limiter.enforce("signup:client-b", detail="Too many signup attempts.")

    with pytest.raises(HTTPException) as exc_info:
        await limiter.enforce("signup:client-a", detail="Too many signup attempts.")
    assert exc_info.value.status_code == 429

    # A different unseen key should still be accepted.
    await limiter.enforce("signup:client-c", detail="Too many signup attempts.")


def _build_request(
    *,
    client_host: str,
    x_forwarded_for: str | None = None,
    x_real_ip: str | None = None,
) -> Request:
    headers: list[tuple[bytes, bytes]] = []
    if x_forwarded_for is not None:
        headers.append((b"x-forwarded-for", x_forwarded_for.encode("utf-8")))
    if x_real_ip is not None:
        headers.append((b"x-real-ip", x_real_ip.encode("utf-8")))

    scope = {
        "type": "http",
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": "/",
        "query_string": b"",
        "headers": headers,
        "client": (client_host, 12345),
        "server": ("testserver", 80),
    }
    return Request(scope)


def test_client_identifier_prefers_real_ip_when_forwarded_for_invalid(monkeypatch):
    monkeypatch.setattr(rate_limit_module.settings, "trust_proxy_headers", True)
    monkeypatch.setattr(
        rate_limit_module,
        "_trusted_proxy_networks",
        [ipaddress.ip_network("10.0.0.0/8")],
    )
    request = _build_request(
        client_host="10.1.2.3",
        x_forwarded_for="not-an-ip",
        x_real_ip="203.0.113.7",
    )

    assert _client_identifier(request) == "203.0.113.7"


def test_client_identifier_falls_back_to_source_ip_when_proxy_headers_invalid(monkeypatch):
    monkeypatch.setattr(rate_limit_module.settings, "trust_proxy_headers", True)
    monkeypatch.setattr(
        rate_limit_module,
        "_trusted_proxy_networks",
        [ipaddress.ip_network("10.0.0.0/8")],
    )
    request = _build_request(
        client_host="10.9.8.7",
        x_forwarded_for="bad-value",
        x_real_ip="also-bad",
    )

    assert _client_identifier(request) == "10.9.8.7"


def test_client_identifier_ignores_forwarded_headers_for_untrusted_source(monkeypatch):
    monkeypatch.setattr(rate_limit_module.settings, "trust_proxy_headers", True)
    monkeypatch.setattr(
        rate_limit_module,
        "_trusted_proxy_networks",
        [ipaddress.ip_network("192.168.0.0/16")],
    )
    request = _build_request(
        client_host="10.9.8.7",
        x_forwarded_for="203.0.113.12",
        x_real_ip="203.0.113.13",
    )

    assert _client_identifier(request) == "10.9.8.7"
