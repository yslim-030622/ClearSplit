"""Tests for shopping endpoints."""

import io
from datetime import date, datetime, timezone
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.shopping_session import ShoppingSession, ShoppingSessionStatus
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
    assert len(data["participants"]) == 1
    assert data["participants"][0]["membership_id"] == str(membership.id)
    assert data["items"] == []
    assert data["receipts"] == []


@pytest.mark.asyncio
async def test_viewer_cannot_create_shopping_session(
    client: AsyncClient, session: AsyncSession
):
    """Viewers should have read-only access and cannot create sessions."""
    owner = create_test_user(email="shop-owner@example.com", username="shopowner")
    viewer = create_test_user(email="shop-viewer@example.com", username="shopviewer")
    session.add_all([owner, viewer])
    await session.flush()

    group = Group(name="Viewer Shopping Group", currency="USD")
    session.add(group)
    await session.flush()

    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    viewer_membership = Membership(
        group_id=group.id, user_id=viewer.id, role=MembershipRole.VIEWER
    )
    session.add_all([owner_membership, viewer_membership])
    await session.flush()

    access_token = create_access_token(viewer.id, viewer.email)
    response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "title": "Viewer Shopping",
            "shopping_date": str(date.today()),
            "paid_by": str(viewer_membership.id),
        },
    )

    assert response.status_code == 403


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
async def test_set_session_participants_resplits_items_and_allows_item_customization(
    client: AsyncClient, session: AsyncSession
):
    """Changing participants re-splits existing items across all participants."""
    user1 = create_test_user(email="resplit1@example.com", username="resplit1")
    user2 = create_test_user(email="resplit2@example.com", username="resplit2")
    user3 = create_test_user(email="resplit3@example.com", username="resplit3")
    session.add_all([user1, user2, user3])
    await session.flush()

    group = Group(name="Resplit Group", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    membership3 = Membership(group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    access_token = create_access_token(user1.id, user1.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    assert create_session_response.status_code == 201
    shopping_session_id = create_session_response.json()["id"]

    initial_participants_response = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"participant_membership_ids": [str(membership1.id), str(membership2.id)]},
    )
    assert initial_participants_response.status_code == 200

    create_item_response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/items",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"name": "Eggs", "total_cents": 1000},
    )
    assert create_item_response.status_code == 201
    item_id = create_item_response.json()["id"]

    custom_sharers_response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"membership_ids": [str(membership1.id)]},
    )
    assert custom_sharers_response.status_code == 200
    assert [row["share_cents"] for row in custom_sharers_response.json()["splits"]] == [1000]

    resplit_response = await client.put(
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
    assert resplit_response.status_code == 200, resplit_response.text
    resplit_data = resplit_response.json()
    assert len(resplit_data["participants"]) == 3

    updated_item = next(item for item in resplit_data["items"] if item["id"] == item_id)
    assert len(updated_item["splits"]) == 3
    shares = sorted([row["share_cents"] for row in updated_item["splits"]], reverse=True)
    assert shares == [334, 333, 333]
    share_members = {row["membership_id"] for row in updated_item["splits"]}
    assert share_members == {str(membership1.id), str(membership2.id), str(membership3.id)}
    assert sum(shares) == 1000

    # Users can still customize item sharers later from the item section.
    customize_again_response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"membership_ids": [str(membership2.id), str(membership3.id)]},
    )
    assert customize_again_response.status_code == 200, customize_again_response.text
    customized_splits = customize_again_response.json()["splits"]
    assert len(customized_splits) == 2
    assert sorted([row["share_cents"] for row in customized_splits]) == [500, 500]
    assert {row["membership_id"] for row in customized_splits} == {
        str(membership2.id),
        str(membership3.id),
    }


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
async def test_session_participant_can_create_item(client: AsyncClient, session: AsyncSession):
    """Any participant (not just payer) can create items."""
    user1 = create_test_user(email="payer@example.com", username="payer")
    user2 = create_test_user(email="participant@example.com", username="participant")
    session.add_all([user1, user2])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2])
    await session.flush()

    payer_token = create_access_token(user1.id, user1.email)
    participant_token = create_access_token(user2.id, user2.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    session_id = create_session_response.json()["id"]

    set_participants_response = await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"participant_membership_ids": [str(membership1.id), str(membership2.id)]},
    )
    assert set_participants_response.status_code == 200

    create_item_response = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {participant_token}"},
        json={"name": "Bread", "total_cents": 350},
    )
    assert create_item_response.status_code == 201, create_item_response.text
    assert create_item_response.json()["created_by_membership_id"] == str(membership2.id)


@pytest.mark.asyncio
async def test_non_participant_cannot_create_item(client: AsyncClient, session: AsyncSession):
    """Non-participants cannot create items in a session."""
    user1 = create_test_user(email="payer2@example.com", username="payer2")
    user2 = create_test_user(email="participant2@example.com", username="participant2")
    user3 = create_test_user(email="outsider2@example.com", username="outsider2")
    session.add_all([user1, user2, user3])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    membership3 = Membership(group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    payer_token = create_access_token(user1.id, user1.email)
    outsider_token = create_access_token(user3.id, user3.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    session_id = create_session_response.json()["id"]

    await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"participant_membership_ids": [str(membership1.id), str(membership2.id)]},
    )

    create_item_response = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {outsider_token}"},
        json={"name": "Forbidden", "total_cents": 400},
    )
    assert create_item_response.status_code == 403


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

    # Payer should receive the extra cent when included among sharers.
    shares_by_member = {row["membership_id"]: row["share_cents"] for row in data["splits"]}
    assert shares_by_member[str(membership1.id)] == 334


@pytest.mark.asyncio
async def test_sharer_remainder_fallback_without_payer(
    client: AsyncClient, session: AsyncSession
):
    """When payer is excluded, deterministic UUID order gets remainder cents."""
    user1 = create_test_user(email="payer-round@example.com", username="payerround")
    user2 = create_test_user(email="user-round2@example.com", username="userround2")
    user3 = create_test_user(email="user-round3@example.com", username="userround3")
    session.add_all([user1, user2, user3])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    membership3 = Membership(group_id=group.id, user_id=user3.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    token = create_access_token(user1.id, user1.email)
    created_session = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    session_id = created_session.json()["id"]

    await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "participant_membership_ids": [
                str(membership1.id),
                str(membership2.id),
                str(membership3.id),
            ]
        },
    )

    item_response = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Fallback Split", "total_cents": 1001},
    )
    item_id = item_response.json()["id"]

    sharers_response = await client.put(
        f"/items/{item_id}/sharers",
        headers={"Authorization": f"Bearer {token}"},
        json={"membership_ids": [str(membership2.id), str(membership3.id)]},
    )
    assert sharers_response.status_code == 200, sharers_response.text

    splits = sharers_response.json()["splits"]
    shares_by_member = {row["membership_id"]: row["share_cents"] for row in splits}
    first_member = min([membership2.id, membership3.id], key=lambda value: str(value))
    second_member = membership3.id if first_member == membership2.id else membership2.id
    assert shares_by_member[str(first_member)] == 501
    assert shares_by_member[str(second_member)] == 500


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
async def test_item_creator_permissions_and_overrides(
    client: AsyncClient, session: AsyncSession
):
    """Item creator can edit/delete, payer can override, unrelated member cannot."""
    payer = create_test_user(email="payer-perm@example.com", username="payerperm")
    creator = create_test_user(email="creator-perm@example.com", username="creatorperm")
    outsider = create_test_user(email="outsider-perm@example.com", username="outsiderperm")
    session.add_all([payer, creator, outsider])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    payer_membership = Membership(group_id=group.id, user_id=payer.id, role=MembershipRole.OWNER)
    creator_membership = Membership(group_id=group.id, user_id=creator.id, role=MembershipRole.MEMBER)
    outsider_membership = Membership(group_id=group.id, user_id=outsider.id, role=MembershipRole.MEMBER)
    session.add_all([payer_membership, creator_membership, outsider_membership])
    await session.flush()

    payer_token = create_access_token(payer.id, payer.email)
    creator_token = create_access_token(creator.id, creator.email)
    outsider_token = create_access_token(outsider.id, outsider.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(payer_membership.id)},
    )
    session_id = create_session_response.json()["id"]

    await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={
            "participant_membership_ids": [
                str(payer_membership.id),
                str(creator_membership.id),
                str(outsider_membership.id),
            ]
        },
    )

    created_item = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {creator_token}"},
        json={"name": "Managed Item", "total_cents": 700},
    )
    assert created_item.status_code == 201, created_item.text
    item_id = created_item.json()["id"]

    # Unrelated non-owner/non-payer/non-creator member cannot update.
    denied_update = await client.patch(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {outsider_token}"},
        json={"name": "Hack", "quantity": 1, "total_cents": 700},
    )
    assert denied_update.status_code == 403

    # Creator can update.
    allowed_update = await client.patch(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {creator_token}"},
        json={"name": "Managed Item Updated", "quantity": 1, "total_cents": 700},
    )
    assert allowed_update.status_code == 200, allowed_update.text
    assert allowed_update.json()["name"] == "Managed Item Updated"

    # Outsider cannot delete.
    denied_delete = await client.delete(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {outsider_token}"},
    )
    assert denied_delete.status_code == 403

    # Payer can override delete.
    allowed_delete = await client.delete(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {payer_token}"},
    )
    assert allowed_delete.status_code == 204


@pytest.mark.asyncio
async def test_group_owner_can_override_item_permissions(
    client: AsyncClient, session: AsyncSession
):
    """Group owner override works even when owner is not session payer."""
    owner = create_test_user(email="owner-override@example.com", username="owneroverride")
    payer = create_test_user(email="payer-override@example.com", username="payeroverride")
    creator = create_test_user(email="creator-override@example.com", username="creatoroverride")
    session.add_all([owner, payer, creator])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    owner_membership = Membership(group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER)
    payer_membership = Membership(group_id=group.id, user_id=payer.id, role=MembershipRole.MEMBER)
    creator_membership = Membership(group_id=group.id, user_id=creator.id, role=MembershipRole.MEMBER)
    session.add_all([owner_membership, payer_membership, creator_membership])
    await session.flush()

    owner_token = create_access_token(owner.id, owner.email)
    payer_token = create_access_token(payer.id, payer.email)
    creator_token = create_access_token(creator.id, creator.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(payer_membership.id)},
    )
    session_id = create_session_response.json()["id"]

    await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={
            "participant_membership_ids": [
                str(owner_membership.id),
                str(payer_membership.id),
                str(creator_membership.id),
            ]
        },
    )

    created_item = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {creator_token}"},
        json={"name": "Owner Managed", "total_cents": 450},
    )
    item_id = created_item.json()["id"]

    owner_update = await client.patch(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {owner_token}"},
        json={"name": "Owner Updated", "quantity": 1, "total_cents": 450},
    )
    assert owner_update.status_code == 200, owner_update.text
    assert owner_update.json()["name"] == "Owner Updated"


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
async def test_finalize_shopping_session(client: AsyncClient, session: AsyncSession):
    """Payer can finalize a shopping session."""
    user = create_test_user(email="finalize@example.com", username="finalize")
    session.add(user)
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership = Membership(group_id=group.id, user_id=user.id, role=MembershipRole.OWNER)
    session.add(membership)
    await session.flush()

    token = create_access_token(user.id, user.email)
    create_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {token}"},
        json={"title": "Finalizable", "paid_by": str(membership.id)},
    )
    session_id = create_response.json()["id"]

    finalize_response = await client.post(
        f"/shopping-sessions/{session_id}/finalize",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert finalize_response.status_code == 200, finalize_response.text
    assert finalize_response.json()["status"] == "finalized"
    assert finalize_response.json()["finalized_at"] is not None


@pytest.mark.asyncio
async def test_reactivating_session_clears_timestamps(
    client: AsyncClient, session: AsyncSession
):
    """Manual ACTIVE status transition clears stale settlement/finalization timestamps."""
    user = create_test_user(email="reactivate@example.com", username="reactivate")
    session.add(user)
    await session.flush()

    group = Group(name="Reactivation Group", currency="USD")
    session.add(group)
    await session.flush()

    membership = Membership(group_id=group.id, user_id=user.id, role=MembershipRole.OWNER)
    session.add(membership)
    await session.flush()

    token = create_access_token(user.id, user.email)
    create_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {token}"},
        json={"title": "Reactivation Target", "paid_by": str(membership.id)},
    )
    session_id = create_response.json()["id"]

    finalized = await client.post(
        f"/shopping-sessions/{session_id}/finalize",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert finalized.status_code == 200, finalized.text
    assert finalized.json()["status"] == "finalized"
    assert finalized.json()["finalized_at"] is not None

    reactivated = await client.patch(
        f"/shopping-sessions/{session_id}",
        headers={"Authorization": f"Bearer {token}"},
        json={"status": "active"},
    )
    assert reactivated.status_code == 200, reactivated.text
    assert reactivated.json()["status"] == "active"
    assert reactivated.json()["settled_at"] is None
    assert reactivated.json()["finalized_at"] is None


@pytest.mark.asyncio
async def test_item_update_reopens_settled_session_and_clears_timestamps(
    client: AsyncClient, session: AsyncSession
):
    """Editing items should reopen settled sessions and clear stale timestamps."""
    user = create_test_user(email="settled-item-edit@example.com", username="settleditem")
    session.add(user)
    await session.flush()

    group = Group(name="Settled Reopen Group", currency="USD")
    session.add(group)
    await session.flush()

    membership = Membership(group_id=group.id, user_id=user.id, role=MembershipRole.OWNER)
    session.add(membership)
    await session.flush()

    token = create_access_token(user.id, user.email)
    create_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {token}"},
        json={"title": "Settled Session", "paid_by": str(membership.id)},
    )
    session_id = create_response.json()["id"]

    participants_response = await client.put(
        f"/shopping-sessions/{session_id}/participants",
        headers={"Authorization": f"Bearer {token}"},
        json={"participant_membership_ids": [str(membership.id)]},
    )
    assert participants_response.status_code == 200, participants_response.text

    item_response = await client.post(
        f"/shopping-sessions/{session_id}/items",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Milk", "total_cents": 399},
    )
    assert item_response.status_code == 201, item_response.text
    item_id = item_response.json()["id"]

    finalized = await client.post(
        f"/shopping-sessions/{session_id}/finalize",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert finalized.status_code == 200, finalized.text
    assert finalized.json()["finalized_at"] is not None

    shopping_session = await session.get(ShoppingSession, UUID(session_id))
    assert shopping_session is not None
    now = datetime.now(tz=timezone.utc)
    shopping_session.status = ShoppingSessionStatus.SETTLED
    shopping_session.settled_at = now
    if shopping_session.finalized_at is None:
        shopping_session.finalized_at = now
    await session.commit()

    updated_item = await client.patch(
        f"/items/{item_id}",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "name": "Milk Updated",
            "quantity": 1,
            "total_cents": 450,
        },
    )
    assert updated_item.status_code == 200, updated_item.text

    refreshed = await client.get(
        f"/shopping-sessions/{session_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["status"] == "active"
    assert refreshed.json()["settled_at"] is None
    assert refreshed.json()["finalized_at"] is None


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
    assert data["uploaded_by_membership_id"] == str(membership.id)
    assert "storage_key" in data
    assert "content_type" in data
    assert data["content_type"] == "image/jpeg"


@pytest.mark.asyncio
async def test_non_participant_cannot_upload_receipt(
    client: AsyncClient, session: AsyncSession
):
    """Test that only session participants can upload receipts."""
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

    # User2 is a group member but not a session participant; upload should fail.
    access_token2 = create_access_token(user2.id, user2.email)
    receipt_content = b"fake receipt image data"
    receipt_file = ("receipt.jpg", io.BytesIO(receipt_content), "image/jpeg")
    response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {access_token2}"},
        files={"file": receipt_file},
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_participant_can_upload_receipt_and_only_one_receipt_allowed(
    client: AsyncClient, session: AsyncSession
):
    """A participant can upload the first receipt, but second upload is rejected."""
    user1 = create_test_user(email="payer-upload@example.com", username="payerupload")
    user2 = create_test_user(email="participant-upload@example.com", username="participantupload")
    session.add_all([user1, user2])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2])
    await session.flush()

    payer_token = create_access_token(user1.id, user1.email)
    participant_token = create_access_token(user2.id, user2.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    assert create_session_response.status_code == 201
    shopping_session_id = create_session_response.json()["id"]

    set_participants_response = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"participant_membership_ids": [str(membership1.id), str(membership2.id)]},
    )
    assert set_participants_response.status_code == 200

    first_upload = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {participant_token}"},
        files={"file": ("receipt.jpg", io.BytesIO(b"fake receipt bytes"), "image/jpeg")},
    )
    assert first_upload.status_code == 201
    assert first_upload.json()["uploaded_by_membership_id"] == str(membership2.id)

    second_upload = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {payer_token}"},
        files={"file": ("receipt-2.jpg", io.BytesIO(b"another fake receipt"), "image/jpeg")},
    )
    assert second_upload.status_code == 409
    assert "Only one receipt is allowed" in second_upload.json()["detail"]


@pytest.mark.asyncio
async def test_only_receipt_uploader_can_delete_receipt(
    client: AsyncClient, session: AsyncSession
):
    """Only the uploader can delete a receipt."""
    user1 = create_test_user(email="payer-delete@example.com", username="payerdelete")
    user2 = create_test_user(email="uploader-delete@example.com", username="uploaderdelete")
    session.add_all([user1, user2])
    await session.flush()

    group = Group(name="Test Household", currency="USD")
    session.add(group)
    await session.flush()

    membership1 = Membership(group_id=group.id, user_id=user1.id, role=MembershipRole.OWNER)
    membership2 = Membership(group_id=group.id, user_id=user2.id, role=MembershipRole.MEMBER)
    session.add_all([membership1, membership2])
    await session.flush()

    payer_token = create_access_token(user1.id, user1.email)
    uploader_token = create_access_token(user2.id, user2.email)

    create_session_response = await client.post(
        f"/groups/{group.id}/shopping-sessions",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"title": "Trip", "paid_by": str(membership1.id)},
    )
    assert create_session_response.status_code == 201
    shopping_session_id = create_session_response.json()["id"]

    set_participants_response = await client.put(
        f"/shopping-sessions/{shopping_session_id}/participants",
        headers={"Authorization": f"Bearer {payer_token}"},
        json={"participant_membership_ids": [str(membership1.id), str(membership2.id)]},
    )
    assert set_participants_response.status_code == 200

    upload_response = await client.post(
        f"/shopping-sessions/{shopping_session_id}/receipt",
        headers={"Authorization": f"Bearer {uploader_token}"},
        files={"file": ("receipt.jpg", io.BytesIO(b"fake receipt bytes"), "image/jpeg")},
    )
    assert upload_response.status_code == 201
    receipt_id = upload_response.json()["id"]

    delete_by_non_uploader = await client.delete(
        f"/receipts/{receipt_id}",
        headers={"Authorization": f"Bearer {payer_token}"},
    )
    assert delete_by_non_uploader.status_code == 403
    assert "uploader" in delete_by_non_uploader.json()["detail"].lower()

    delete_by_uploader = await client.delete(
        f"/receipts/{receipt_id}",
        headers={"Authorization": f"Bearer {uploader_token}"},
    )
    assert delete_by_uploader.status_code == 200
    assert delete_by_uploader.json()["deleted"] is True


# ============================================================================
# OCR Tests
# ============================================================================


@pytest.mark.asyncio
async def test_extract_items_from_receipt_success(
    client: AsyncClient, session: AsyncSession, monkeypatch
):
    """Test that extract-items returns pre-existing items with correct fields.

    Phase 4 changed the contract: the first call when no items exist returns
    202 (job enqueued).  When items are already present it returns 200 directly.
    We pre-insert items so the endpoint takes the 200-path and we can assert
    the response shape without depending on the Celery worker.
    """
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from uuid import UUID

    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

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

    # Pre-insert extracted items directly (simulates a completed OCR job)
    session.add_all([
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Bananas",
            quantity=2,
            unit_price_cents=150,
            total_cents=300,
            raw_line="2 x Bananas 3.00",
            confidence=0.95,
        ),
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Milk",
            quantity=1,
            unit_price_cents=None,
            total_cents=499,
            raw_line="Milk 4.99",
            confidence=0.88,
        ),
    ])
    await session.flush()

    # Items exist → endpoint returns 200 directly
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
async def test_extract_items_non_uploader_forbidden(
    client: AsyncClient, session: AsyncSession
):
    """Test that non-uploader cannot extract items from receipt."""
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
    
    # User2 (non-uploader) tries to extract items (should fail)
    access_token2 = create_access_token(user2.id, user2.email)
    response = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token2}"},
    )

    assert response.status_code == 403
    assert "uploader" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_extract_items_idempotent(
    client: AsyncClient, session: AsyncSession, monkeypatch
):
    """Test that extract-items returns existing items on every call (idempotent).

    Phase 4 changed the first call (no items) to return 202.  We pre-insert
    items so both calls take the 200-path and return identical results.
    """
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from uuid import UUID

    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

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

    # Pre-insert item (simulates a completed OCR job)
    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Test Item",
            quantity=1,
            unit_price_cents=None,
            total_cents=100,
            raw_line="Test Item 1.00",
            confidence=0.9,
        )
    )
    await session.flush()

    # First extraction — items exist → 200
    response1 = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response1.status_code == 200
    items1 = response1.json()
    assert len(items1) == 1

    # Second extraction — same items returned without re-running OCR
    response2 = await client.post(
        f"/receipts/{receipt_id}/extract-items",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response2.status_code == 200
    items2 = response2.json()
    assert len(items2) == 1
    assert items2[0]["id"] == items1[0]["id"]  # Same item ID returned both times


@pytest.mark.asyncio
async def test_get_extracted_items(client: AsyncClient, session: AsyncSession, monkeypatch):
    """Test that any group member can fetch previously extracted items via GET.

    Phase 4 changed POST extract-items to return 202 on first call, so we
    pre-insert items directly and test only the GET extracted-items path.
    """
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from uuid import UUID

    monkeypatch.setattr("app.worker.tasks.run_receipt_ocr.delay", lambda *_, **__: None)

    # Create users (uploader and member)
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

    # Pre-insert extracted item directly (simulates a completed OCR job)
    session.add(
        ReceiptExtractedItem(
            receipt_upload_id=UUID(receipt_id),
            name="Item A",
            quantity=1,
            unit_price_cents=None,
            total_cents=100,
            raw_line="Item A 1.00",
            confidence=0.9,
        )
    )
    await session.flush()

    # User2 (member, not uploader) can read extracted items via GET
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
