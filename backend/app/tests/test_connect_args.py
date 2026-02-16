import ssl

import pytest

from app.db.connect_args import build_asyncpg_engine_config


def test_sslmode_require_maps_to_ssl_connect_arg() -> None:
    engine_url, connect_args = build_asyncpg_engine_config(
        "postgresql+asyncpg://user:pass@db.example.com:5432/app?sslmode=require",
        env_name="staging",
        connect_timeout_seconds=5.0,
    )

    assert engine_url == "postgresql+asyncpg://user:pass@db.example.com:5432/app"
    assert isinstance(connect_args["ssl"], ssl.SSLContext)


def test_ssl_true_maps_to_ssl_connect_arg() -> None:
    engine_url, connect_args = build_asyncpg_engine_config(
        "postgresql+asyncpg://user:pass@db.example.com:5432/app?ssl=true",
        env_name="staging",
        connect_timeout_seconds=5.0,
    )

    assert engine_url == "postgresql+asyncpg://user:pass@db.example.com:5432/app"
    assert isinstance(connect_args["ssl"], ssl.SSLContext)


def test_ssl_false_maps_to_disabled_ssl_connect_arg() -> None:
    engine_url, connect_args = build_asyncpg_engine_config(
        "postgresql+asyncpg://user:pass@db.example.com:5432/app?ssl=false",
        env_name="staging",
        connect_timeout_seconds=5.0,
    )

    assert engine_url == "postgresql+asyncpg://user:pass@db.example.com:5432/app"
    assert connect_args["ssl"] is False


def test_non_local_defaults_to_tls_when_missing_ssl_config() -> None:
    _, connect_args = build_asyncpg_engine_config(
        "postgresql+asyncpg://user:pass@db.example.com:5432/app",
        env_name="staging",
        connect_timeout_seconds=5.0,
    )

    assert isinstance(connect_args["ssl"], ssl.SSLContext)


def test_local_does_not_force_tls_when_missing_ssl_config() -> None:
    _, connect_args = build_asyncpg_engine_config(
        "postgresql+asyncpg://user:pass@db.example.com:5432/app",
        env_name="local",
        connect_timeout_seconds=5.0,
    )

    assert "ssl" not in connect_args


def test_rejects_conflicting_ssl_and_sslmode() -> None:
    with pytest.raises(RuntimeError, match="both sslmode and ssl"):
        build_asyncpg_engine_config(
            "postgresql+asyncpg://user:pass@db.example.com:5432/app?ssl=true&sslmode=require",
            env_name="staging",
            connect_timeout_seconds=5.0,
        )


def test_rejects_invalid_ssl_value() -> None:
    with pytest.raises(RuntimeError, match="Unsupported ssl value"):
        build_asyncpg_engine_config(
            "postgresql+asyncpg://user:pass@db.example.com:5432/app?ssl=bogus",
            env_name="staging",
            connect_timeout_seconds=5.0,
        )

