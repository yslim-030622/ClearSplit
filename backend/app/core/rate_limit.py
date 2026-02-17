"""Simple in-memory rate limiting helpers for abuse-prone endpoints."""

from __future__ import annotations

import asyncio
import ipaddress
import logging
import time
from collections.abc import Callable
from collections import defaultdict, deque
from typing import Union
from uuid import UUID

from fastapi import HTTPException, Request, status

from app.core.config import get_settings


IPNetwork = Union[ipaddress.IPv4Network, ipaddress.IPv6Network]

settings = get_settings()
_rate_limit_enabled = settings.env.lower() != "test"
logger = logging.getLogger(__name__)

# This limiter is intentionally process-local.
# In multi-replica production deployments each instance enforces its own counters,
# so aggregate limits are weaker than single-instance behavior.
if settings.env.lower() == "production":
    logger.warning(
        "Rate limiting backend is process-local memory. "
        "Use a shared store (e.g. Redis) for strict global limits across replicas."
    )


def _parse_trusted_proxy_networks() -> list[IPNetwork]:
    networks: list[IPNetwork] = []
    for raw in settings.get_trusted_proxy_ips():
        try:
            if "/" in raw:
                networks.append(ipaddress.ip_network(raw, strict=False))
            else:
                ip = ipaddress.ip_address(raw)
                networks.append(
                    ipaddress.ip_network(f"{ip}/32" if ip.version == 4 else f"{ip}/128")
                )
        except ValueError:
            # Ignore invalid entries so a bad env value does not crash the app.
            continue
    return networks


_trusted_proxy_networks = _parse_trusted_proxy_networks()


def _normalize_client_value(value: str, *, allow_non_ip: bool = False) -> str:
    candidate = value.strip()
    if not candidate:
        return ""

    try:
        return str(ipaddress.ip_address(candidate))
    except ValueError:
        if allow_non_ip:
            # Keep non-IP values stable without trusting arbitrary formatting.
            return candidate.lower()
        return ""


def _is_request_from_trusted_proxy(request: Request) -> bool:
    if not settings.trust_proxy_headers:
        return False

    if not _trusted_proxy_networks:
        return False

    if not request.client or not request.client.host:
        return False

    try:
        source_ip = ipaddress.ip_address(request.client.host)
    except ValueError:
        return False

    return any(source_ip in network for network in _trusted_proxy_networks)


class InMemoryRateLimiter:
    """A small process-local sliding window limiter."""

    def __init__(
        self,
        limit: int,
        window_seconds: int,
        max_keys: int,
        now_fn: Callable[[], float] | None = None,
    ):
        self.limit = limit
        self.window_seconds = window_seconds
        self.max_keys = max(1000, max_keys)
        self._now = now_fn or time.monotonic
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._last_seen: dict[str, float] = {}
        self._lock = asyncio.Lock()
        self._next_cleanup = 0.0

    def _prune_old_entries(self, now: float) -> None:
        # Run global cleanup at most once per window to keep hot path cheap.
        if now < self._next_cleanup:
            return
        self._next_cleanup = now + self.window_seconds
        cutoff = now - self.window_seconds

        stale_keys = [key for key, seen_at in self._last_seen.items() if seen_at < cutoff]
        for key in stale_keys:
            self._events.pop(key, None)
            self._last_seen.pop(key, None)

    def _evict_lru_keys(self, count: int) -> None:
        if count <= 0:
            return

        oldest = sorted(self._last_seen.items(), key=lambda item: item[1])[:count]
        for key, _ in oldest:
            self._events.pop(key, None)
            self._last_seen.pop(key, None)

    async def enforce(self, key: str, detail: str) -> None:
        now = self._now()
        cutoff = now - self.window_seconds

        async with self._lock:
            self._prune_old_entries(now)

            if key not in self._events and len(self._events) >= self.max_keys:
                # Drop oldest keys first to avoid unbounded memory growth.
                self._evict_lru_keys(max(1, self.max_keys // 10))
            if key not in self._events and len(self._events) >= self.max_keys:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Rate limiter is saturated. Please try again later.",
                )

            entries = self._events[key]
            while entries and entries[0] < cutoff:
                entries.popleft()

            if len(entries) >= self.limit:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=detail,
                )

            entries.append(now)
            self._last_seen[key] = now


def _client_identifier(request: Request) -> str:
    if _is_request_from_trusted_proxy(request):
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            normalized = _normalize_client_value(forwarded.split(",")[0])
            if normalized:
                return normalized

        real_ip = _normalize_client_value(request.headers.get("x-real-ip", ""))
        if real_ip:
            return real_ip

    if request.client and request.client.host:
        normalized = _normalize_client_value(request.client.host, allow_non_ip=True)
        if normalized:
            return normalized

    return "unknown"


_login_limiter = InMemoryRateLimiter(
    limit=10,
    window_seconds=60,
    max_keys=settings.rate_limit_max_keys,
)
_signup_limiter = InMemoryRateLimiter(
    limit=5,
    window_seconds=300,
    max_keys=settings.rate_limit_max_keys,
)
_member_preview_limiter = InMemoryRateLimiter(
    limit=30,
    window_seconds=60,
    max_keys=settings.rate_limit_max_keys,
)


async def enforce_login_rate_limit(request: Request) -> None:
    if not _rate_limit_enabled:
        return
    await _login_limiter.enforce(
        key=f"login:{_client_identifier(request)}",
        detail="Too many login attempts. Please try again later.",
    )


async def enforce_signup_rate_limit(request: Request) -> None:
    if not _rate_limit_enabled:
        return
    await _signup_limiter.enforce(
        key=f"signup:{_client_identifier(request)}",
        detail="Too many signup attempts. Please try again later.",
    )


async def enforce_member_preview_rate_limit(
    request: Request, user_id: UUID, group_id: UUID
) -> None:
    if not _rate_limit_enabled:
        return
    await _member_preview_limiter.enforce(
        key=f"member-preview:{group_id}:{user_id}:{_client_identifier(request)}",
        detail="Too many member preview requests. Please try again later.",
    )
