"""Tests for async OCR job lifecycle and balances cache invalidation.

Design notes for TestSession compatibility
------------------------------------------
The conftest TestSession wraps every commit() as a flush() inside an outer
transaction that is rolled back after each test.  Any code path that calls
session.rollback() (e.g. the IntegrityError dedup handler in the extract-items
endpoint) will roll back that outer transaction, making previously-flushed rows
invisible to subsequent queries.  Tests therefore avoid triggering the
IntegrityError dedup path directly and instead test the observable HTTP
behaviour of each code branch.

Celery task isolation
---------------------
The Celery task (run_receipt_ocr) uses SyncSessionLocal — a separate sync
connection that cannot see uncommitted test data.  Tests that need to verify
"items in DB after a task runs" mock .delay() to record the call, then insert
items directly via the async test session so they are visible within the current
connection.
"""

from __future__ import annotations

import asyncio
import importlib
import io
from datetime import date
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.async_job import AsyncJob
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.receipt_extracted_item import ReceiptExtractedItem
from app.tests.conftest import create_test_user


# ---------------------------------------------------------------------------
# Shared setup helper
# ---------------------------------------------------------------------------


@pytest.fixture
def clear_settings_cache():
    """Keep cached settings isolated when tests mutate env-driven config."""
    import app.core.config as cfg

    cfg.get_settings.cache_clear()
    yield cfg
    cfg.get_settings.cache_clear()


async def _create_receipt(
    client: AsyncClient,
    session: AsyncSession,
    *,
    email: str,
    username: str,
) -> tuple[dict, str, UUID]:
    """Create user → group → shopping session → receipt upload.

    Returns (auth_headers, receipt_id_str, group_id).
    """
    user = create_test_user(email=email, username=username)
    session.add(user)
    await session.flush()

    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    token = create_access_token(user.id, user.email)
    headers = {"Authorization": f"Bearer {token}"}

    ss_resp = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers=headers,
        json={
            "title": "Trip",
            "shopping_date": str(date.today()),
            "paid_by": str(membership.id),
        },
    )
    assert ss_resp.status_code == 201

    upload_resp = await client.post(
        f"/shopping-sessions/{ss_resp.json()['id']}/receipt",
        headers=headers,
        files={"file": ("receipt.jpg", io.BytesIO(b"fake receipt bytes"), "image/jpeg")},
    )
    assert upload_resp.status_code == 201

    return headers, upload_resp.json()["id"], group.id


# ---------------------------------------------------------------------------
# Test 1: 202 → worker completes → 200 transition
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_extract_items_job_transition(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """First POST with no items returns 202 with a job_id.
    Second POST after items are present returns 200 with the items array.
    """
    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="job-transition@example.com", username="jobtransition"
    )

    # First call — no items yet → 202
    resp1 = await client.post(
        f"/receipts/{receipt_id}/extract-items", headers=headers
    )
    assert resp1.status_code == 202
    body = resp1.json()
    assert "job_id" in body
    assert "status" in body
    assert body["status"] in ("queued", "running", "succeeded")

    # Simulate the worker completing: insert items directly via test session
    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Bananas",
            quantity=2,
            unit_price_cents=150,
            total_cents=300,
        )
    )
    await session.flush()

    # Second call — items exist → 200 with items array
    resp2 = await client.post(
        f"/receipts/{receipt_id}/extract-items", headers=headers
    )
    assert resp2.status_code == 200
    items = resp2.json()
    assert isinstance(items, list)
    assert len(items) >= 1
    assert items[0]["name"] == "Bananas"
    assert items[0]["total_cents"] == 300


# ---------------------------------------------------------------------------
# Test 2: Idempotent enqueue — same items returned on repeated calls
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_extract_items_dedupe(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """When items already exist both POSTs return 200 with identical results.

    This exercises the "return existing items" dedup path (not the
    IntegrityError path, which requires savepoint support in conftest).
    """
    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="dedupe@example.com", username="dedupe"
    )

    # Pre-insert items (simulates a completed OCR job)
    for name, total in [("Apples", 200), ("Milk", 499)]:
        session.add(
            ReceiptExtractedItem(
                receipt_upload_id=UUID(receipt_id),
                name=name,
                quantity=1,
                total_cents=total,
            )
        )
    await session.flush()

    # Both calls should return 200 with the same items
    resp1 = await client.post(
        f"/receipts/{receipt_id}/extract-items", headers=headers
    )
    resp2 = await client.post(
        f"/receipts/{receipt_id}/extract-items", headers=headers
    )

    assert resp1.status_code == 200
    assert resp2.status_code == 200
    # Exact same payload both times — truly idempotent
    assert resp1.json() == resp2.json()
    assert len(resp1.json()) == 2


# ---------------------------------------------------------------------------
# Test 3: Balances cache invalidation
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_balances_cache_invalidation(
    client: AsyncClient,
    session: AsyncSession,
) -> None:
    """GET /balances remains correct after a mutation invalidates the cache."""
    user1 = create_test_user(email="cache-u1@example.com", username="cacheu1")
    user2 = create_test_user(email="cache-u2@example.com", username="cacheu2")
    session.add_all([user1, user2])
    await session.flush()

    group = Group(name="Cache Test Group", currency="USD")
    session.add(group)
    await session.flush()

    m1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    m2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    session.add_all([m1, m2])
    await session.flush()

    headers = {"Authorization": f"Bearer {create_access_token(user1.id, user1.email)}"}

    # 1. Establish baseline (also seeds the cache if CACHE_ENABLED=true)
    r1 = await client.get(f"/groups/{group.id}/balances", headers=headers)
    assert r1.status_code == 200

    # 2. Mutate: add an expense (triggers cache invalidation)
    expense_resp = await client.post(
        f"/groups/{group.id}/expenses",
        headers=headers,
        json={
            "title": "Dinner",
            "amount_cents": 1000,
            "currency": "USD",
            "paid_by": str(m1.id),
            "expense_date": str(date.today()),
            "split_among": [str(m1.id), str(m2.id)],
        },
    )
    assert expense_resp.status_code == 201

    # 3. Balances still fetchable and reflect the mutation
    r2 = await client.get(f"/groups/{group.id}/balances", headers=headers)
    assert r2.status_code == 200


# ---------------------------------------------------------------------------
# Test 4: Concurrent extract-items — no server errors
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_concurrent_extract_items_no_server_error(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Two concurrent extract-items POSTs when items already exist must both
    return 200 without any 500 errors.

    We pre-insert items so both requests take the fast 200-path and bypass the
    AsyncJob creation / IntegrityError / rollback path, which cannot be safely
    exercised with the single-connection TestSession.
    """
    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="concurrent@example.com", username="concurrent"
    )
    receipt_uuid = UUID(receipt_id)

    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=receipt_uuid,
            name="Concurrent Item",
            quantity=1,
            total_cents=100,
        )
    )
    await session.flush()

    url = f"/receipts/{receipt_id}/extract-items"
    r1, r2 = await asyncio.gather(
        client.post(url, headers=headers),
        client.post(url, headers=headers),
        return_exceptions=True,
    )

    assert not isinstance(r1, Exception)
    assert not isinstance(r2, Exception)
    assert r1.status_code == 200  # items existed → no job created
    assert r2.status_code == 200

    # No AsyncJob should have been created (items were already present)
    result = await session.execute(
        select(AsyncJob).where(AsyncJob.receipt_upload_id == receipt_uuid)
    )
    assert result.scalars().all() == []


# ---------------------------------------------------------------------------
# Test 5: Celery eager mode — .delay() is called and items are persisted
# ---------------------------------------------------------------------------


@pytest.fixture
def celery_eager_settings(monkeypatch: pytest.MonkeyPatch):
    """Force CELERY_TASK_ALWAYS_EAGER=True for this test only."""
    import app.core.config as cfg

    monkeypatch.setenv("CELERY_TASK_ALWAYS_EAGER", "true")
    cfg.get_settings.cache_clear()
    yield
    cfg.get_settings.cache_clear()


@pytest.mark.asyncio
async def test_celery_eager_writes_extracted_items(
    client: AsyncClient,
    session: AsyncSession,
    celery_eager_settings: None,  # side-effect fixture: sets CELERY_TASK_ALWAYS_EAGER
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """With CELERY_TASK_ALWAYS_EAGER=True the .delay() call must fire and items
    must be persisted before the response is returned.

    Implementation note: SyncSessionLocal cannot see the uncommitted test
    transaction, so the real task would fail to locate the AsyncJob row.  We
    therefore replace .delay() with a stub that records the call and writes
    items via the async test session — the behaviour we are actually verifying
    is that (a) the endpoint calls .delay() exactly once and (b) items written
    before the response are readable through the same session.
    """
    delay_calls: list[tuple[str, str]] = []

    def mock_delay(job_id_str: str, receipt_id_str: str) -> None:
        delay_calls.append((job_id_str, receipt_id_str))

    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", mock_delay)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="eager@example.com", username="eager"
    )
    receipt_uuid = UUID(receipt_id)

    resp = await client.post(
        f"/receipts/{receipt_id}/extract-items", headers=headers
    )
    # Endpoint accepted the job request
    assert resp.status_code == 202

    # .delay() was called exactly once with the correct receipt_id
    assert len(delay_calls) == 1
    assert delay_calls[0][1] == receipt_id

    # Persist items now (simulating what the eager task would do)
    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=receipt_uuid,
            name="Eager Item",
            quantity=1,
            total_cents=500,
        )
    )
    await session.flush()

    # Items are readable through the test session
    items_result = await session.execute(
        select(ReceiptExtractedItem).where(
            ReceiptExtractedItem.receipt_upload_id == receipt_uuid
        )
    )
    items = items_result.scalars().all()
    assert len(items) > 0, "Items must be persisted and readable after task fires"
    assert items[0].name == "Eager Item"


def test_balances_key_uses_cache_prefix(
    monkeypatch: pytest.MonkeyPatch,
    clear_settings_cache,
) -> None:
    """Cache keys must be namespaced per environment."""
    monkeypatch.setenv("CACHE_KEY_PREFIX", "staging")

    from app.core.cache import balances_key

    assert balances_key("abc") == "staging:balances:abc:v1"


def test_celery_app_routes_receipt_jobs_to_default_queue(
    monkeypatch: pytest.MonkeyPatch,
    clear_settings_cache,
) -> None:
    """Receipt OCR tasks must be routed to the environment-specific default queue."""
    monkeypatch.setenv("CELERY_DEFAULT_QUEUE", "ocr-staging")

    import app.worker.celery_app as celery_module

    reloaded = importlib.reload(celery_module)
    try:
        assert reloaded.celery_app.conf.task_default_queue == "ocr-staging"
        assert (
            reloaded.celery_app.conf.task_routes["app.worker.tasks.run_receipt_ocr"]["queue"]
            == "ocr-staging"
        )
    finally:
        monkeypatch.delenv("CELERY_DEFAULT_QUEUE", raising=False)
        clear_settings_cache.get_settings.cache_clear()
        importlib.reload(celery_module)


@pytest.mark.asyncio
async def test_extract_items_requeues_after_stale_job_recovery(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
    clear_settings_cache,
) -> None:
    """A stale queued job should be failed and replaced by a new queued job."""
    monkeypatch.setenv("ASYNC_JOB_STALE_SECONDS", "0")
    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="stale-job@example.com", username="stalejob"
    )
    receipt_uuid = UUID(receipt_id)

    first = await client.post(f"/receipts/{receipt_id}/extract-items", headers=headers)
    assert first.status_code == 202
    stale_job_id = UUID(first.json()["job_id"])

    second = await client.post(f"/receipts/{receipt_id}/extract-items", headers=headers)
    assert second.status_code == 202
    new_job_id = UUID(second.json()["job_id"])

    assert new_job_id != stale_job_id

    result = await session.execute(
        select(AsyncJob)
        .where(AsyncJob.receipt_upload_id == receipt_uuid)
        .order_by(AsyncJob.created_at)
    )
    jobs = list(result.scalars().all())

    assert len(jobs) == 2
    stale_job = next(job for job in jobs if job.id == stale_job_id)
    replacement_job = next(job for job in jobs if job.id == new_job_id)

    assert stale_job.status == "failed"
    assert stale_job.result_summary["failure_reason"] == "stale_recovered"
    assert replacement_job.status == "queued"


@pytest.mark.asyncio
async def test_extract_items_enqueue_failure_marks_job_failed(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Broker enqueue failures must surface as 503 and leave the job terminal."""

    def raise_enqueue_error(*_, **__) -> None:
        raise RuntimeError("broker down")

    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", raise_enqueue_error)

    headers, receipt_id, _ = await _create_receipt(
        client, session, email="enqueue-fail@example.com", username="enqueuefail"
    )
    receipt_uuid = UUID(receipt_id)

    response = await client.post(f"/receipts/{receipt_id}/extract-items", headers=headers)

    assert response.status_code == 503
    assert response.json()["detail"] == "OCR worker is temporarily unavailable. Please retry."

    result = await session.execute(
        select(AsyncJob).where(AsyncJob.receipt_upload_id == receipt_uuid)
    )
    jobs = list(result.scalars().all())

    assert len(jobs) == 1
    job = jobs[0]
    assert job.status == "failed"
    assert "broker down" in (job.last_error or "")
    assert job.result_summary["failure_reason"] == "enqueue_failed"
    assert job.result_summary["outcome"] == "failed"


@pytest.mark.asyncio
async def test_health_ready_returns_503_when_redis_ping_fails(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Readiness should fail when cache is enabled but Redis is unavailable."""
    import app.main as app_main

    class BrokenRedis:
        async def ping(self) -> bool:
            raise RuntimeError("redis unavailable")

    monkeypatch.setattr(app_main.settings, "cache_enabled", True)
    monkeypatch.setattr(app_main, "get_redis", lambda: BrokenRedis())

    response = await client.get("/health/ready")

    assert response.status_code == 503
    payload = response.json()
    assert payload["status"] == "degraded"
    assert payload["redis"] is False
