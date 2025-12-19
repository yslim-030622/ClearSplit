"""Tests for groups and memberships endpoints."""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import create_access_token
from app.auth.password import hash_password
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User


@pytest.mark.asyncio
async def test_create_group(client: AsyncClient, session: AsyncSession):
    """Test creating a group."""
    # Create user
    user = User(email="owner@example.com", password_hash=hash_password("password123"))
    session.add(user)
    await session.commit()

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
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    session.add_all([user1, user2])
    await session.commit()

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
    await session.commit()

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
    user = User(email="user@example.com", password_hash=hash_password("password123"))
    group = Group(name="Test Group", currency="USD")
    session.add_all([user, group])
    await session.flush()

    membership = Membership(
        group_id=group.id, user_id=user.id, role=MembershipRole.MEMBER
    )
    session.add(membership)
    await session.commit()

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
    user1 = User(email="user1@example.com", password_hash=hash_password("password123"))
    user2 = User(email="user2@example.com", password_hash=hash_password("password123"))
    group = Group(name="Test Group", currency="USD")
    session.add_all([user1, user2, group])
    await session.flush()

    # Only user1 is member
    membership = Membership(
        group_id=group.id, user_id=user1.id, role=MembershipRole.MEMBER
    )
    session.add(membership)
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    new_member = User(
        email="member@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, new_member])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    new_member = User(
        email="member@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, new_member])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    member = User(
        email="member@example.com", password_hash=hash_password("password123")
    )
    new_member = User(
        email="new@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, member, new_member])
    await session.commit()

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
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    existing_member = User(
        email="member@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, existing_member])
    await session.commit()

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
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    member1 = User(
        email="member1@example.com", password_hash=hash_password("password123")
    )
    member2 = User(
        email="member2@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, member1, member2])
    await session.commit()

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
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    non_member = User(
        email="nonmember@example.com", password_hash=hash_password("password123")
    )
    session.add_all([owner, non_member])
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.commit()

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
    owner = User(
        email="owner@example.com", password_hash=hash_password("password123")
    )
    session.add(owner)
    await session.commit()

    # Create group
    group = Group(name="Test Group", currency="USD")
    session.add(group)
    await session.flush()

    # Add owner
    owner_membership = Membership(
        group_id=group.id, user_id=owner.id, role=MembershipRole.OWNER
    )
    session.add(owner_membership)
    await session.commit()

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

