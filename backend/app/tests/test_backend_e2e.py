"""End-to-end smoke coverage across backend domains."""

from datetime import date
import io
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.async_job import AsyncJob
from app.models.receipt_extracted_item import ReceiptExtractedItem


def _auth_header(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
@pytest.mark.e2e
async def test_backend_end_to_end_smoke(
    client: AsyncClient,
    session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
):
    """Exercise auth, groups, expenses, settlements, shopping, and receipt OCR APIs."""
    from app.services.ocr import ExtractedItem

    async def fake_ocr_extract(_image_bytes: bytes) -> list[ExtractedItem]:
        return [
            ExtractedItem(
                name="Milk",
                quantity=1,
                unit_price_cents=499,
                total_cents=499,
                raw_line="Milk 4.99",
                confidence=0.95,
            )
        ]

    monkeypatch.setattr("app.services.ocr.extract_items_from_receipt", fake_ocr_extract)
    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    live = await client.get("/health/live")
    assert live.status_code == 200
    assert live.json() == {"status": "ok"}

    health = await client.get("/health")
    assert health.status_code in {200, 503}
    health_payload = health.json()
    assert health_payload["database"] is True
    assert "s3" in health_payload
    if health.status_code == 503:
        assert health_payload["status"] == "degraded"
        assert health_payload["redis"] is False

    owner_signup = await client.post(
        "/auth/signup",
        json={
            "username": "owner_e2e",
            "email": "owner.e2e@example.com",
            "password": "password123",
            "first_name": "Owner",
            "last_name": "User",
        },
    )
    assert owner_signup.status_code == 201, owner_signup.text
    owner = owner_signup.json()
    owner_token = owner["access_token"]
    owner_user_id = owner["user"]["id"]

    member_signup = await client.post(
        "/auth/signup",
        json={
            "username": "member_e2e",
            "email": "member.e2e@example.com",
            "password": "password123",
            "first_name": "Member",
            "last_name": "User",
        },
    )
    assert member_signup.status_code == 201, member_signup.text
    member = member_signup.json()
    member_token = member["access_token"]

    create_group = await client.post(
        "/groups",
        headers=_auth_header(owner_token),
        json={"name": "E2E Group", "currency": "USD"},
    )
    assert create_group.status_code == 201, create_group.text
    group_id = create_group.json()["id"]

    list_groups = await client.get("/groups", headers=_auth_header(owner_token))
    assert list_groups.status_code == 200
    assert any(group["id"] == group_id for group in list_groups.json())

    group_details = await client.get(f"/groups/{group_id}", headers=_auth_header(owner_token))
    assert group_details.status_code == 200
    assert group_details.json()["name"] == "E2E Group"

    members = await client.get(f"/groups/{group_id}/members", headers=_auth_header(owner_token))
    assert members.status_code == 200
    owner_membership_id = next(
        membership["id"]
        for membership in members.json()
        if membership["user_id"] == owner_user_id
    )

    preview_before_add = await client.post(
        f"/groups/{group_id}/members/preview",
        headers=_auth_header(owner_token),
        json={"email": "member.e2e@example.com"},
    )
    assert preview_before_add.status_code == 200
    preview_before_payload = preview_before_add.json()
    assert preview_before_payload["found"] is True
    assert preview_before_payload["already_member"] is False

    add_member = await client.post(
        f"/groups/{group_id}/members",
        headers=_auth_header(owner_token),
        json={"email": "member.e2e@example.com", "role": "member"},
    )
    assert add_member.status_code == 201, add_member.text
    member_membership_id = add_member.json()["id"]

    preview_after_add = await client.post(
        f"/groups/{group_id}/members/preview",
        headers=_auth_header(owner_token),
        json={"email": "member.e2e@example.com"},
    )
    assert preview_after_add.status_code == 200
    preview_after_payload = preview_after_add.json()
    assert preview_after_payload["found"] is True
    assert preview_after_payload["already_member"] is True

    create_expense = await client.post(
        f"/groups/{group_id}/expenses",
        headers=_auth_header(owner_token),
        json={
            "title": "E2E Dinner",
            "amount_cents": 6000,
            "currency": "USD",
            "paid_by": owner_membership_id,
            "expense_date": str(date.today()),
            "split_among": [owner_membership_id, member_membership_id],
        },
    )
    assert create_expense.status_code == 201, create_expense.text
    expense_payload = create_expense.json()
    expense_id = expense_payload["id"]
    assert sum(split["share_cents"] for split in expense_payload["splits"]) == 6000

    list_expenses = await client.get(
        f"/groups/{group_id}/expenses",
        headers=_auth_header(owner_token),
    )
    assert list_expenses.status_code == 200
    assert any(expense["id"] == expense_id for expense in list_expenses.json())

    get_expense = await client.get(f"/expenses/{expense_id}", headers=_auth_header(owner_token))
    assert get_expense.status_code == 200
    assert get_expense.json()["id"] == expense_id

    balances = await client.get(f"/groups/{group_id}/balances", headers=_auth_header(owner_token))
    assert balances.status_code == 200
    balances_payload = balances.json()
    assert len(balances_payload["balances"]) == 2
    assert len(balances_payload["suggestions"]) >= 1

    compute_settlements = await client.post(
        f"/groups/{group_id}/settlements/compute",
        headers=_auth_header(owner_token),
    )
    assert compute_settlements.status_code == 201, compute_settlements.text
    settlement_batch_payload = compute_settlements.json()
    assert settlement_batch_payload["total_settlements"] >= 1

    latest_settlements = await client.get(
        f"/groups/{group_id}/settlements/latest",
        headers=_auth_header(owner_token),
    )
    assert latest_settlements.status_code == 200
    assert latest_settlements.json()["id"] == settlement_batch_payload["id"]

    create_session = await client.post(
        f"/groups/{group_id}/shopping-sessions",
        headers=_auth_header(owner_token),
        json={
            "title": "E2E Grocery",
            "shopping_date": str(date.today()),
            "paid_by": owner_membership_id,
        },
    )
    assert create_session.status_code == 201, create_session.text
    shopping_session_id = create_session.json()["id"]

    set_participants = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers=_auth_header(owner_token),
        json={"participant_membership_ids": [owner_membership_id, member_membership_id]},
    )
    assert set_participants.status_code == 200, set_participants.text
    assert len(set_participants.json()["participants"]) == 2

    create_item = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers=_auth_header(owner_token),
        json={"name": "Milk", "quantity": 2, "unit_price_cents": 250},
    )
    assert create_item.status_code == 201, create_item.text
    item_payload = create_item.json()
    assert item_payload["total_cents"] == 500
    item_id = item_payload["id"]

    set_sharers = await client.put(
        f"/items/{item_id}/sharers",
        headers=_auth_header(owner_token),
        json={"membership_ids": [owner_membership_id, member_membership_id]},
    )
    assert set_sharers.status_code == 200, set_sharers.text
    sharers_payload = set_sharers.json()
    assert sum(split["share_cents"] for split in sharers_payload["splits"]) == 500

    upload_receipt = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers=_auth_header(owner_token),
        files={"file": ("receipt.jpg", io.BytesIO(b"fake receipt bytes"), "image/jpeg")},
    )
    assert upload_receipt.status_code == 201, upload_receipt.text
    receipt_id = upload_receipt.json()["id"]

    download_receipt_url = await client.get(
        f"/receipts/{receipt_id}/download-url",
        headers=_auth_header(owner_token),
    )
    assert download_receipt_url.status_code == 200, download_receipt_url.text
    assert download_receipt_url.json()["url"].startswith("https://test-storage.local/")

    extracted = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers=_auth_header(owner_token),
    )
    assert extracted.status_code == 202, extracted.text
    job_id = extracted.json()["job_id"]

    job_result = await session.execute(select(AsyncJob).where(AsyncJob.id == UUID(job_id)))
    job = job_result.scalar_one()
    job.status = "succeeded"
    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Milk",
            quantity=1,
            unit_price_cents=499,
            total_cents=499,
            raw_line="Milk 4.99",
            confidence=0.95,
        )
    )
    await session.flush()

    job_status = await client.get(f"/jobs/{job_id}", headers=_auth_header(owner_token))
    assert job_status.status_code == 200, job_status.text
    assert job_status.json()["status"] == "succeeded"

    extracted_for_member = await client.get(
        f"/receipts/{receipt_id}/extracted-items",
        headers=_auth_header(member_token),
    )
    assert extracted_for_member.status_code == 200, extracted_for_member.text
    assert extracted_for_member.json()[0]["name"] == "Milk"

    finalize_session = await client.post(
        f"/shopping-sessions/{shopping_session_id}/finalize",
        headers=_auth_header(owner_token),
    )
    assert finalize_session.status_code == 200, finalize_session.text
    assert finalize_session.json()["status"] == "finalized"
