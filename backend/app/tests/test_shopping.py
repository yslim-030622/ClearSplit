"""Tests for shopping endpoints."""

import io
import uuid
from datetime import date

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.tests.conftest import create_test_user


@pytest.mark.asyncio
async def test_create_shopping_session(client: AsyncClient, session: AsyncSession):
    """Test creating a shopping session."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "shopping_date": str(date.today()),
            "paid_by": str(membership.id),
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Costco Trip"
    assert data["group_id"] == str(group.id)
    assert data["paid_by_membership_id"] == str(membership.id)
    assert data["currency"] == "USD"
    assert data["participants"] == []
    assert data["items"] == []
    assert data["receipts"] == []


@pytest.mark.asyncio
async def test_set_session_participants(client: AsyncClient, session: AsyncSession):
    """Test setting participants for a shopping session."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    user3 = create_test_user(email="user3@example.com", username="user3")
    session.add_all([user1, user2, user3])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    # Get access token for user1 (payer)
    access_token = create_access_token(user1.id, user1.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership1.id),
        },
    )
    assert response.status_code == 201
    shopping_session_id = response.json()["id"]

    # Set participants
    response = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "participant_membership_ids": [
                str(membership1.id),
                str(membership2.id),
            ]
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data["participants"]) == 2
    participant_ids = {p["membership_id"] for p in data["participants"]}
    assert str(membership1.id) in participant_ids
    assert str(membership2.id) in participant_ids


@pytest.mark.asyncio
async def test_non_payer_cannot_set_participants(
    client: AsyncClient, session: AsyncSession
):
    """Test that non-payer cannot set participants."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    session.add_all([user1, user2])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2])
    await session.flush()

    # User1 creates shopping session
    access_token1 = create_access_token(user1.id, user1.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token1}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership1.id),
        },
    )
    assert response.status_code == 201
    shopping_session_id = response.json()["id"]

    # User2 tries to set participants (should fail)
    access_token2 = create_access_token(user2.id, user2.email)
    response = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token2}"},
        json={
            "participant_membership_ids": [str(membership1.id), str(membership2.id)]
        },
    )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_create_shopping_item(client: AsyncClient, session: AsyncSession):
    """Test creating a shopping item."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership.id),
        },
    )
    assert response.status_code == 201
    shopping_session_id = response.json()["id"]

    # Create item with unit price
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "name": "Milk (2 gallons)",
            "quantity": 2,
            "unit_price_cents": 399,
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Milk (2 gallons)"
    assert data["quantity"] == 2
    assert data["unit_price_cents"] == 399
    assert data["total_cents"] == 798
    assert data["splits"] == []


@pytest.mark.asyncio
async def test_create_item_with_total_only(client: AsyncClient, session: AsyncSession):
    """Test creating an item with only total_cents (no unit price)."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership.id),
        },
    )
    shopping_session_id = response.json()["id"]

    # Create item with total only (e.g., tax)
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "name": "Sales Tax",
            "total_cents": 125,
        },
    )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Sales Tax"
    assert data["quantity"] == 1
    assert data["unit_price_cents"] is None
    assert data["total_cents"] == 125


@pytest.mark.asyncio
async def test_set_item_sharers_equal_split(client: AsyncClient, session: AsyncSession):
    """Test setting sharers for an item with equal split."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    user3 = create_test_user(email="user3@example.com", username="user3")
    session.add_all([user1, user2, user3])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]

    # Set participants
    await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "participant_membership_ids": [
                str(membership1.id),
                str(membership2.id),
                str(membership3.id),
            ]
        },
    )

    # Create item
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "name": "Shared Snacks",
            "total_cents": 1000,
        },
    )
    item_id = response.json()["id"]

    # Set sharers (all 3 people)
    response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "membership_ids": [
                str(membership1.id),
                str(membership2.id),
                str(membership3.id),
            ]
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["total_cents"] == 1000
    assert len(data["splits"]) == 3

    # Verify equal split with remainder (334, 333, 333)
    share_amounts = sorted([s["share_cents"] for s in data["splits"]], reverse=True)
    assert share_amounts == [334, 333, 333]
    assert sum(share_amounts) == 1000


@pytest.mark.asyncio
async def test_set_item_sharers_subset_of_participants(
    client: AsyncClient, session: AsyncSession
):
    """Test setting sharers that are a subset of session participants."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    user3 = create_test_user(email="user3@example.com", username="user3")
    session.add_all([user1, user2, user3])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]

    # Set participants (all 3)
    await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "participant_membership_ids": [
                str(membership1.id),
                str(membership2.id),
                str(membership3.id),
            ]
        },
    )

    # Create item
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "name": "Vegan Snacks",
            "total_cents": 500,
        },
    )
    item_id = response.json()["id"]

    # Set sharers (only 2 people - user1 and user2)
    response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"membership_ids": [str(membership1.id), str(membership2.id)]},
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data["splits"]) == 2

    # Verify equal split (250 each)
    share_amounts = [s["share_cents"] for s in data["splits"]]
    assert sorted(share_amounts) == [250, 250]


@pytest.mark.asyncio
async def test_sharers_must_be_participants(client: AsyncClient, session: AsyncSession):
    """Test that sharers must be session participants."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    user3 = create_test_user(email="user3@example.com", username="user3")
    session.add_all([user1, user2, user3])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    # Get access token
    access_token = create_access_token(user1.id, user1.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]

    # Set participants (only user1 and user2)
    await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "participant_membership_ids": [str(membership1.id), str(membership2.id)]
        },
    )

    # Create item
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "name": "Shared Item",
            "total_cents": 600,
        },
    )
    item_id = response.json()["id"]

    # Try to set sharers including user3 (not a participant)
    response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "membership_ids": [
                str(membership1.id),
                str(membership2.id),
                str(membership3.id),
            ]
        },
    )

    assert response.status_code == 400


@pytest.mark.asyncio
async def test_list_shopping_sessions(client: AsyncClient, session: AsyncSession):
    """Test listing shopping sessions for a group."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create multiple shopping sessions
    await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"title": "Costco Trip 1", "paid_by": str(membership.id)},
    )
    await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"title": "Trader Joe's", "paid_by": str(membership.id)},
    )

    # List sessions
    response = await client.get(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    titles = {s["title"] for s in data}
    assert "Costco Trip 1" in titles
    assert "Trader Joe's" in titles


@pytest.mark.asyncio
async def test_get_shopping_session(client: AsyncClient, session: AsyncSession):
    """Test getting a specific shopping session with all data."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"title": "Costco Trip", "paid_by": str(membership.id)},
    )
    shopping_session_id = response.json()["id"]

    # Set participants
    await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"participant_membership_ids": [str(membership.id)]},
    )

    # Create item
    await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"name": "Milk", "total_cents": 399},
    )

    # Get session
    response = await client.get(
        f"/shopping-sessions/{shopping_session_id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Costco Trip"
    assert len(data["participants"]) == 1
    assert len(data["items"]) == 1
    assert data["items"][0]["name"] == "Milk"


@pytest.mark.asyncio
async def test_non_member_cannot_view_session(
    client: AsyncClient, session: AsyncSession
):
    """Test that non-members cannot view a shopping session."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    session.add_all([user1, user2])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership for user1 only
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    session.add(membership1)
    await session.flush()

    # User1 creates shopping session
    access_token1 = create_access_token(user1.id, user1.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token1}"},
        json={"title": "Costco Trip", "paid_by": str(membership1.id)},
    )
    shopping_session_id = response.json()["id"]

    # User2 tries to view session (should fail)
    access_token2 = create_access_token(user2.id, user2.email)
    response = await client.get(
        f"/shopping-sessions/{shopping_session_id}",
        headers={"Authorization": f"Bearer {access_token2}"},
    )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_upload_receipt(client: AsyncClient, session: AsyncSession):
    """Test uploading a receipt for a shopping session."""
    # Create user
    user = create_test_user(email="user@example.com", username="testuser")
    session.add(user)
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add membership
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create shopping session
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Costco Trip",
            "shopping_date": str(date.today()),
            "paid_by": str(membership.id),
        },
    )
    assert response.status_code == 201
    shopping_session_id = response.json()["id"]

    # Upload receipt
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 201
    data = response.json()
    assert "id" in data
    assert "session_id" in data
    assert data["session_id"] == str(shopping_session_id)
    assert "storage_key" in data
    assert "content_type" in data
    assert data["content_type"] == "image/jpeg"


@pytest.mark.asyncio
async def test_non_payer_cannot_upload_receipt(
    client: AsyncClient, session: AsyncSession
):
    """Test that only the payer can upload receipts."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    session.add_all([user1, user2])
    await session.flush()

    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2])
    await session.flush()

    # User1 creates shopping session (payer)
    access_token1 = create_access_token(user1.id, user1.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token1}"},
        json={
            "title": "Costco Trip",
            "shopping_date": str(date.today()),
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]

    # User2 tries to upload receipt (should fail)
    access_token2 = create_access_token(user2.id, user2.email)
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token2}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 403


# ============================================================================
# OCR Tests
# ============================================================================


@pytest.mark.asyncio
async def test_extract_items_from_receipt_success(
    client: AsyncClient, session: AsyncSession, monkeypatch
):
    """Test successful OCR extraction of items from receipt."""
    from app.services.ocr import ExtractedItem
    
    # Mock OCR function to return test data
    def mock_extract(image_bytes: bytes):
        return [
            ExtractedItem(
                name="Bananas",
                quantity=2,
                unit_price_cents=150,
                total_cents=300,
                raw_line="2 x Bananas 3.00",
                confidence=0.95,
            ),
            ExtractedItem(
                name="Milk",
                quantity=1,
                unit_price_cents=None,
                total_cents=499,
                raw_line="Milk 4.99",
                confidence=0.88,
            ),
        ]
    
    monkeypatch.setattr("app.services.shopping.extract_items_from_receipt", mock_extract)
    
    # Mock S3 download
    def mock_get_bytes(storage_key: str):
        return b"fake image data"
    
    from app.services.shopping import receipt_storage
    monkeypatch.setattr(receipt_storage, "get_receipt_bytes", mock_get_bytes)
    
    # Create user and group
    user = create_test_user(email="payer@example.com", username="payer")
    session.add(user)
    await session.flush()
    
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()
    
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()
    
    # Create shopping session
    access_token = create_access_token(user.id, user.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Grocery Run",
            "shopping_date": str(date.today()),
            "paid_by": str(membership.id),
        },
    )
    shopping_session_id = response.json()["id"]
    
    # Upload receipt
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 201
    receipt_id = response.json()["id"]
    
    # Extract items using OCR
    response = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    
    assert response.status_code == 200
    items = response.json()
    assert len(items) == 2
    
    # Check first item
    assert items[0]["name"] == "Bananas"
    assert items[0]["quantity"] == 2
    assert items[0]["unit_price_cents"] == 150
    assert items[0]["total_cents"] == 300
    assert items[0]["confidence"] == 0.95
    
    # Check second item
    assert items[1]["name"] == "Milk"
    assert items[1]["quantity"] == 1
    assert items[1]["unit_price_cents"] is None
    assert items[1]["total_cents"] == 499
    assert items[1]["confidence"] == 0.88


@pytest.mark.asyncio
async def test_extract_items_non_payer_forbidden(
    client: AsyncClient, session: AsyncSession
):
    """Test that non-payer cannot extract items from receipt."""
    # Create users
    user1 = create_test_user(email="payer@example.com", username="payer")
    user2 = create_test_user(email="member@example.com", username="member")
    session.add_all([user1, user2])
    await session.flush()
    
    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()
    
    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2])
    await session.flush()
    
    # User1 (payer) creates shopping session
    access_token1 = create_access_token(user1.id, user1.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token1}"},
        json={
            "title": "Grocery Run",
            "shopping_date": str(date.today()),
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]
    
    # User1 uploads receipt
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token1}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 201
    receipt_id = response.json()["id"]
    
    # User2 (non-payer) tries to extract items (should fail)
    access_token2 = create_access_token(user2.id, user2.email)
    response = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token2}"},
    )
    
    assert response.status_code == 403
    assert "payer" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_extract_items_idempotent(
    client: AsyncClient, session: AsyncSession, monkeypatch
):
    """Test that extracting items twice returns existing items (idempotent)."""
    from app.services.ocr import ExtractedItem
    
    # Track how many times OCR is called
    ocr_call_count = [0]
    
    def mock_extract(image_bytes: bytes):
        ocr_call_count[0] += 1
        return [
            ExtractedItem(
                name="Test Item",
                quantity=1,
                unit_price_cents=None,
                total_cents=100,
                raw_line="Test Item 1.00",
                confidence=0.9,
            ),
        ]
    
    monkeypatch.setattr("app.services.shopping.extract_items_from_receipt", mock_extract)
    
    # Mock S3 download
    def mock_get_bytes(storage_key: str):
        return b"fake image data"
    
    from app.services.shopping import receipt_storage
    monkeypatch.setattr(receipt_storage, "get_receipt_bytes", mock_get_bytes)
    
    # Create user and group
    user = create_test_user(email="payer@example.com", username="payer")
    session.add(user)
    await session.flush()
    
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()
    
    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.OWNER
    )
    session.add(membership)
    await session.flush()
    
    # Create shopping session
    access_token = create_access_token(user.id, user.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Grocery Run",
            "shopping_date": str(date.today()),
            "paid_by": str(membership.id),
        },
    )
    shopping_session_id = response.json()["id"]
    
    # Upload receipt
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 201
    receipt_id = response.json()["id"]
    
    # First extraction
    response1 = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response1.status_code == 200
    items1 = response1.json()
    assert len(items1) == 1
    assert ocr_call_count[0] == 1  # OCR was called once
    
    # Second extraction (should return existing items)
    response2 = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response2.status_code == 200
    items2 = response2.json()
    assert len(items2) == 1
    assert items2[0]["id"] == items1[0]["id"]  # Same item ID
    assert ocr_call_count[0] == 1  # OCR was NOT called again


@pytest.mark.asyncio
async def test_get_extracted_items(client: AsyncClient, session: AsyncSession, monkeypatch):
    """Test getting previously extracted items."""
    from app.services.ocr import ExtractedItem
    
    # Mock OCR function
    def mock_extract(image_bytes: bytes):
        return [
            ExtractedItem(
                name="Item A",
                quantity=1,
                unit_price_cents=None,
                total_cents=100,
                raw_line="Item A 1.00",
                confidence=0.9,
            ),
        ]
    
    monkeypatch.setattr("app.services.shopping.extract_items_from_receipt", mock_extract)
    
    # Mock S3 download
    def mock_get_bytes(storage_key: str):
        return b"fake image data"
    
    from app.services.shopping import receipt_storage
    monkeypatch.setattr(receipt_storage, "get_receipt_bytes", mock_get_bytes)
    
    # Create users (payer and member)
    user1 = create_test_user(email="payer@example.com", username="payer")
    user2 = create_test_user(email="member@example.com", username="member")
    session.add_all([user1, user2])
    await session.flush()
    
    # Create group
    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()
    
    # Add memberships
    membership1 = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER
    )
    session.add_all([membership1, membership2])
    await session.flush()
    
    # User1 creates shopping session
    access_token1 = create_access_token(user1.id, user1.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token1}"},
        json={
            "title": "Grocery Run",
            "shopping_date": str(date.today()),
            "paid_by": str(membership1.id),
        },
    )
    shopping_session_id = response.json()["id"]
    
    # Upload receipt
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token1}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 201
    receipt_id = response.json()["id"]
    
    # Extract items
    response = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token1}"},
    )
    assert response.status_code == 200
    
    # User2 (member, not payer) gets extracted items (should succeed)
    access_token2 = create_access_token(user2.id, user2.email)
    response = await client.get(
        f"/receipts/{receipt_id}/extracted-items",
        headers={"Authorization": f"Bearer {access_token2}"},
    )
    
    assert response.status_code == 200
    items = response.json()
    assert len(items) == 1
    assert items[0]["name"] == "Item A"
    assert items[0]["total_cents"] == 100

