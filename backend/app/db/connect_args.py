"""Database connection argument helpers shared by runtime and migrations."""

from __future__ import annotations

import ssl
from collections.abc import Mapping

from sqlalchemy.engine import make_url


NON_TLS_ENVS = {"local", "test"}
TLS_SSLMODES = {"allow", "prefer", "require", "verify-ca", "verify-full"}


def normalize_env_name(value: str | None) -> str:
    """Normalize environment name values used for runtime branching."""
    normalized = (value or "local").strip().lower()
    return normalized or "local"


def database_url_has_ssl_settings(database_url: str) -> bool:
    """Return true when the database URL already encodes SSL behavior."""
    query = make_url(database_url).query
    return any(
        key in query
        for key in (
            "ssl",
            "sslmode",
            "sslrootcert",
            "sslcert",
            "sslkey",
            "sslcrl",
        )
    )


def _coerce_query_value(value: object) -> str:
    if isinstance(value, (tuple, list)):
        if not value:
            return ""
        return str(value[0])
    return str(value)


def _ssl_from_sslmode(raw_sslmode: object) -> object:
    sslmode = _coerce_query_value(raw_sslmode).strip().lower()
    if not sslmode:
        return None
    if sslmode == "disable":
        return False
    if sslmode in TLS_SSLMODES:
        return ssl.create_default_context()
    raise RuntimeError(
        f"Unsupported sslmode '{sslmode}' in DATABASE_URL. "
        "Use disable/allow/prefer/require/verify-ca/verify-full."
    )


def build_asyncpg_engine_config(
    database_url: str,
    *,
    env_name: str,
    connect_timeout_seconds: float,
) -> tuple[str, dict[str, object]]:
    """Return SQLAlchemy asyncpg URL + connect args used by app and Alembic."""
    url = make_url(database_url)
    query: dict[str, object] = dict(url.query)

    sslmode_value = query.pop("sslmode", None)
    ssl_from_mode = _ssl_from_sslmode(sslmode_value) if sslmode_value is not None else None

    sanitized_url = url.set(query=cast_query(query))
    connect_args: dict[str, object] = {
        "timeout": connect_timeout_seconds,
    }

    # `sslmode` is not accepted by asyncpg kwargs; map it to `ssl`.
    if sslmode_value is not None:
        connect_args["ssl"] = ssl_from_mode
    elif env_name not in NON_TLS_ENVS and "ssl" not in query:
        # Force TLS by default in non-local environments when URL omits SSL options.
        connect_args["ssl"] = ssl.create_default_context()
    return sanitized_url.render_as_string(hide_password=False), connect_args


def cast_query(query: Mapping[str, object]) -> dict[str, str]:
    """Normalize URL query mapping to plain string values for SQLAlchemy URL.set."""
    return {key: _coerce_query_value(value) for key, value in query.items()}
