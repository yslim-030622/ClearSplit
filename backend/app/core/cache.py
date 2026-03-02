"""Redis cache-aside helpers with best-effort semantics."""

from __future__ import annotations

import json
import logging
from typing import Any

import redis.asyncio as aioredis

from app.core.config import get_settings

logger = logging.getLogger(__name__)

_redis_client: aioredis.Redis | None = None


def get_redis() -> aioredis.Redis | None:
    """Return shared async Redis client, or None if cache is disabled."""
    global _redis_client
    settings = get_settings()
    if not settings.cache_enabled:
        return None
    if _redis_client is None:
        _redis_client = aioredis.from_url(
            settings.redis_url,
            decode_responses=True,
            socket_connect_timeout=2,
        )
    return _redis_client


async def close_redis() -> None:
    """Gracefully close the Redis connection pool on shutdown."""
    global _redis_client
    if _redis_client is not None:
        await _redis_client.aclose()
        _redis_client = None


def balances_key(group_id) -> str:
    """Canonical cache key for group balances."""
    return f"balances:{group_id}:v1"


async def cache_get_json(key: str) -> Any | None:
    """Read and parse a JSON value from cache. Returns None on miss or error."""
    client = get_redis()
    if client is None:
        return None
    try:
        raw = await client.get(key)
        if raw is None:
            return None
        return json.loads(raw)
    except Exception:
        logger.warning("cache_get_json failed for key=%s", key, exc_info=True)
        return None


async def cache_set_json(key: str, value: Any, ttl_seconds: int | None = None) -> None:
    """Write a JSON value to cache. Best-effort — silently fails on error."""
    client = get_redis()
    if client is None:
        return
    try:
        settings = get_settings()
        ttl = ttl_seconds or settings.cache_default_ttl_seconds
        await client.set(key, json.dumps(value, default=str), ex=ttl)
    except Exception:
        logger.warning("cache_set_json failed for key=%s", key, exc_info=True)


async def cache_delete(key: str) -> None:
    """Delete a cache key. Best-effort."""
    client = get_redis()
    if client is None:
        return
    try:
        await client.delete(key)
    except Exception:
        logger.warning("cache_delete failed for key=%s", key, exc_info=True)


async def invalidate_balances_cache(group_id) -> None:
    """Invalidate the balances cache for a given group."""
    key = balances_key(group_id)
    await cache_delete(key)
