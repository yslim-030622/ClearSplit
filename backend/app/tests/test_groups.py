"""Tests for groups and memberships endpoints."""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.tests.conftest import create_test_user


@pytest.mark.asyncio
async def test_create_group(client: AsyncClient, session: AsyncSession):
    """Test creating a group."""
    # Create user
    user = create_test_user(email="owner@example.com", username="owner")
    session.add(user)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Create group
    response = await client.post(
        "/groups",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"name": "Test Group", "currency": "USD"},
    )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Test Group"
    assert data["currency"] == "USD"
    assert "id" in data

    # Verify group was created
    from sqlalchemy import select

    result = await session.execute(select(Group).where(Group.id == data["id"]))
    group = result.scalar_one_or_none()
    assert group is not None
    assert group.name == "Test Group"

    # Verify creator is owner
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group.id, Membership.user_id == user.id
        )
    )
    membership = result.scalar_one_or_none()
    assert membership is not None
    assert membership.role == MembershipRole.OWNER


@pytest.mark.asyncio
async def test_list_my_groups(client: AsyncClient, session: AsyncSession):
    """Test listing user's groups."""
    # Create users
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    session.add_all([user1, user2])
    await session.flush()

    # Create groups
    group1 = Group(name="Group 1", currency="USD")
    group2 = Group(name="Group 2", currency="EUR")
    session.add_all([group1, group2])
    await session.flush()

    # Add memberships
    membership1 = Membership(
        group_id=group1.id, user_id=user1.id, role=MembershipRole.OWNER
    )
    membership2 = Membership(
        group_id=group2.id, user_id=user1.id, role=MembershipRole.MEMBER
    )
    membership3 = Membership(
        group_id=group2.id, user_id=user2.id, role=MembershipRole.OWNER
    )
    session.add_all([membership1, membership2, membership3])
    await session.flush()

    # Get access token for user1
    access_token = create_access_token(user1.id, user1.email)

    # List groups
    response = await client.get(
        "/groups",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    group_names = [g["name"] for g in data]
    assert "Group 1" in group_names
    assert "Group 2" in group_names


@pytest.mark.asyncio
async def test_get_group(client: AsyncClient, session: AsyncSession):
    """Test getting a specific group."""
    # Create user and group
    user = create_test_user(email="user@example.com", username="testuser")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.MEMBER
    )
    session.add(membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(user.id, user.email)

    # Get group
    response = await client.get(
        f"/groups/{group.id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(group.id)
    assert data["name"] == "Test Group"


@pytest.mark.asyncio
async def test_get_group_not_member(client: AsyncClient, session: AsyncSession):
    """Test getting a group when user is not a member."""
    # Create users and group
    user1 = create_test_user(email="user1@example.com", username="user1")
    user2 = create_test_user(email="user2@example.com", username="user2")
    group = Group(name="Test Group", currency="USD")
    session.add_all([user1, user2, group])
    await session.flush()

    # Only user1 is member
    membership = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.MEMBER
    )
    session.add(membership)
    await session.flush()

    # Get access token for user2
    access_token = create_access_token(user2.id, user2.email)

    # Try to get group
    response = await client.get(
        f"/groups/{group.id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 403
    assert "not a member" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_add_member_by_user_id(client: AsyncClient, session: AsyncSession):
    """Test adding a member by user_id."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    new_member = create_test_user(email="member@example.com", username="member")
    session.add_all([owner, new_member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Add member
    response = await client.post(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"user_id": str(new_member.id), "role": "member"},
    )

    assert response.status_code == 201
    data = response.json()
    assert data["user_id"] == str(new_member.id)
    assert data["role"] == "member"

    # Verify membership was created
    from sqlalchemy import select

    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group.id, Membership.user_id == new_member.id
        )
    )
    membership = result.scalar_one_or_none()
    assert membership is not None


@pytest.mark.asyncio
async def test_add_member_by_email(client: AsyncClient, session: AsyncSession):
    """Test adding a member by email."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    new_member = create_test_user(email="member@example.com", username="member")
    session.add_all([owner, new_member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Add member by email
    response = await client.post(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"email": "member@example.com", "role": "member"},
    )

    assert response.status_code == 201
    data = response.json()
    assert data["user_id"] == str(new_member.id)
    assert data["role"] == "member"


@pytest.mark.asyncio
async def test_add_member_not_owner(client: AsyncClient, session: AsyncSession):
    """Test adding a member when user is not owner."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    member = create_test_user(email="member@example.com", username="member")
    new_member = create_test_user(email="new@example.com", username="newuser")
    session.add_all([owner, member, new_member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    member_membership = Membership(
        group_id=group.id, user_id=member.id, role=MembershipRole.MEMBER
    )
    session.add_all([owner_membership, member_membership])
    await session.flush()

    # Get access token for member (not owner)
    access_token = create_access_token(member.id, member.email)

    # Try to add member
    response = await client.post(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"user_id": str(new_member.id)},
    )

    assert response.status_code == 403
    assert "owner" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_add_member_already_exists(client: AsyncClient, session: AsyncSession):
    """Test adding a member who is already in the group."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    existing_member = create_test_user(email="member@example.com", username="member")
    session.add_all([owner, existing_member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    existing_membership = Membership(
        group_id=group.id, user_id=existing_member.id, role=MembershipRole.MEMBER
    )
    session.add_all([owner_membership, existing_membership])
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Try to add existing member
    response = await client.post(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"user_id": str(existing_member.id)},
    )

    assert response.status_code == 400
    assert "already" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_list_members(client: AsyncClient, session: AsyncSession):
    """Test listing group members."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    member1 = create_test_user(email="member1@example.com", username="member1")
    member2 = create_test_user(email="member2@example.com", username="member2")
    session.add_all([owner, member1, member2])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    member1_membership = Membership(
        group_id=group.id, user_id=member1.id, role=MembershipRole.MEMBER
    )
    member2_membership = Membership(
        group_id=group.id, user_id=member2.id, role=MembershipRole.MEMBER
    )
    session.add_all([owner_membership, member1_membership, member2_membership])
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # List members
    response = await client.get(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    data = response.json()
    assert len(data) == 3
    user_ids = [m["user_id"] for m in data]
    assert str(owner.id) in user_ids
    assert str(member1.id) in user_ids
    assert str(member2.id) in user_ids


@pytest.mark.asyncio
async def test_list_members_not_member(client: AsyncClient, session: AsyncSession):
    """Test listing members when user is not a member."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    non_member = create_test_user(email="nonmember@example.com", username="nonmember")
    session.add_all([owner, non_member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token for non-member
    access_token = create_access_token(non_member.id, non_member.email)

    # Try to list members
    response = await client.get(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 403
    assert "not a member" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_add_member_user_not_found(client: AsyncClient, session: AsyncSession):
    """Test adding a member with non-existent user."""
    # Create owner
    owner = create_test_user(email="owner@example.com", username="owner")
    session.add(owner)
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Try to add non-existent user
    import uuid

    fake_user_id = uuid.uuid4()
    response = await client.post(
        f"/groups/{group.id}/members",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"user_id": str(fake_user_id)},
    )

    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_preview_member_invite_by_email(client: AsyncClient, session: AsyncSession):
    """Test previewing a member invite by email."""
    # Create owner
    owner = create_test_user(email="owner@example.com", username="owner")
    session.add(owner)
    await session.flush()

    # Create user to preview
    user_to_invite = create_test_user(
        email="invitee@example.com", username="invitee"
    )
    session.add(user_to_invite)
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner membership
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Preview invite by email
    response = await client.post(
        f"/groups/{group.id}/members/preview",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"email": "invitee@example.com"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["found"] is True
    assert data["already_member"] is False
    assert data["user"]["email"] == "invitee@example.com"
    assert data["user"]["username"] == "invitee"


@pytest.mark.asyncio
async def test_preview_member_invite_by_username(client: AsyncClient, session: AsyncSession):
    """Test previewing a member invite by username."""
    # Create owner
    owner = create_test_user(email="owner@example.com", username="owner")
    session.add(owner)
    await session.flush()

    # Create user to preview
    user_to_invite = create_test_user(
        email="invitee@example.com", username="invitee"
    )
    session.add(user_to_invite)
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner membership
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Preview invite by username
    response = await client.post(
        f"/groups/{group.id}/members/preview",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"username": "invitee"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["found"] is True
    assert data["already_member"] is False
    assert data["user"]["email"] == "invitee@example.com"
    assert data["user"]["username"] == "invitee"


@pytest.mark.asyncio
async def test_preview_member_invite_already_member(client: AsyncClient, session: AsyncSession):
    """Test previewing a member invite for user who is already a member."""
    # Create owner
    owner = create_test_user(email="owner@example.com", username="owner")
    session.add(owner)
    await session.flush()

    # Create user who is already a member
    existing_member = create_test_user(
        email="member@example.com", username="member"
    )
    session.add(existing_member)
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner membership
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Add existing member
    member_membership = Membership(
        group_id=group.id, user_id=existing_member.id, role=MembershipRole.MEMBER
    )
    session.add(member_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Preview invite for existing member
    response = await client.post(
        f"/groups/{group.id}/members/preview",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"email": "member@example.com"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["found"] is True
    assert data["already_member"] is True
    assert data["membership_id"] == str(member_membership.id)
    assert data["role"] == "member"


@pytest.mark.asyncio
async def test_preview_member_invite_user_not_found(client: AsyncClient, session: AsyncSession):
    """Test previewing a member invite for non-existent user."""
    # Create owner
    owner = create_test_user(email="owner@example.com", username="owner")
    session.add(owner)
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner membership
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    # Get access token
    access_token = create_access_token(owner.id, owner.email)

    # Preview invite for non-existent user
    response = await client.post(
        f"/groups/{group.id}/members/preview",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"email": "nonexistent@example.com"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["found"] is False


@pytest.mark.asyncio
async def test_preview_member_invite_not_owner(client: AsyncClient, session: AsyncSession):
    """Test that only owners can preview member invites."""
    # Create users
    owner = create_test_user(email="owner@example.com", username="owner")
    member = create_test_user(email="member@example.com", username="member")
    session.add_all([owner, member])
    await session.flush()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add memberships
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    member_membership = Membership(
        group_id=group.id, user_id=member.id, role=MembershipRole.MEMBER
    )
    session.add_all([owner_membership, member_membership])
    await session.flush()

    # Get access token for member (not owner)
    access_token = create_access_token(member.id, member.email)

    # Member tries to preview invite (should fail)
    response = await client.post(
        f"/groups/{group.id}/members/preview",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"email": "someone@example.com"},
    )

    assert response.status_code == 403


@pytest.mark.asyncio
async def test_delete_group_owner(client: AsyncClient, session: AsyncSession):
    """Test that a group owner can delete a group."""
    from sqlalchemy import select

    owner = create_test_user(email="owner_delete@example.com", username="owner_delete")
    session.add(owner)
    await session.flush()

    group = Group(name="Delete Me", currency="USD")
    session.add(group)
    await session.flush()

    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.flush()

    access_token = create_access_token(owner.id, owner.email)

    response = await client.delete(
        f"/groups/{group.id}",
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == str(group.id)
    assert payload["name"] == "Delete Me"

    group_result = await session.execute(select(Group).where(Group.id == group.id))
    assert group_result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_delete_group_not_owner(client: AsyncClient, session: AsyncSession):
    """Test that non-owners cannot delete a group."""
    from sqlalchemy import select

    owner = create_test_user(email="owner_keep@example.com", username="owner_keep")
    member = create_test_user(email="member_keep@example.com", username="member_keep")
    session.add_all([owner, member])
    await session.flush()

    group = Group(name="Cannot Delete", currency="USD")
    session.add(group)
    await session.flush()

    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    member_membership = Membership(
        group_id=group.id, user_id=member.id, role=MembershipRole.MEMBER
    )
    session.add_all([owner_membership, member_membership])
    await session.flush()

    member_token = create_access_token(member.id, member.email)

    response = await client.delete(
        f"/groups/{group.id}",
        headers={"Authorization": f"Bearer {member_token}"},
    )

    assert response.status_code == 403

    group_result = await session.execute(select(Group).where(Group.id == group.id))
    assert group_result.scalar_one_or_none() is not None
