"""Group service layer for business logic."""

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.user import User


async def get_user_membership(
    session: AsyncSession, group_id: UUID, user_id: UUID
) -> Membership | None:
    """Get user's membership in a group.

    Args:
        session: Database session
        group_id: Group UUID
        user_id: User UUID

    Returns:
        Membership if exists, None otherwise
    """
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id, Membership.user_id == user_id
        )
    )
    return result.scalar_one_or_none()


async def require_membership(
    session: AsyncSession, group_id: UUID, user_id: UUID
) -> Membership:
    """Require that user is a member of the group.

    Args:
        session: Database session
        group_id: Group UUID
        user_id: User UUID

    Returns:
        Membership

    Raises:
        HTTPException: If user is not a member
    """
    membership = await get_user_membership(session, group_id, user_id)
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )
    return membership


async def require_owner_role(
    session: AsyncSession, group_id: UUID, user_id: UUID
) -> Membership:
    """Require that user is an owner of the group.

    Args:
        session: Database session
        group_id: Group UUID
        user_id: User UUID

    Returns:
        Membership

    Raises:
        HTTPException: If user is not an owner
    """
    membership = await require_membership(session, group_id, user_id)
    if membership.role != MembershipRole.OWNER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only group owners can perform this action",
        )
    return membership


async def get_group_by_id(
    session: AsyncSession, group_id: UUID, user_id: UUID
) -> Group:
    """Get group by ID, ensuring user is a member.

    Args:
        session: Database session
        group_id: Group UUID
        user_id: User UUID

    Returns:
        Group

    Raises:
        HTTPException: If group not found or user is not a member
    """
    result = await session.execute(select(Group).where(Group.id == group_id))
    group = result.scalar_one_or_none()

    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Group not found",
        )

    # Verify user is a member
    await require_membership(session, group_id, user_id)

    return group


async def get_user_groups(
    session: AsyncSession, user_id: UUID
) -> list[Group]:
    """Get all groups where user is a member.

    Args:
        session: Database session
        user_id: User UUID

    Returns:
        List of groups
    """
    result = await session.execute(
        select(Group)
        .join(Membership, Group.id == Membership.group_id)
        .where(Membership.user_id == user_id)
        .order_by(Group.created_at.desc())
    )
    return list(result.scalars().all())


async def create_group_with_owner(
    session: AsyncSession, name: str, currency: str, owner_id: UUID
) -> Group:
    """Create a new group and add creator as owner.

    Args:
        session: Database session
        name: Group name
        currency: Currency code
        owner_id: User UUID of group creator

    Returns:
        Created group
    """
    # Create group
    group = Group(name=name, currency=currency)
    session.add(group)
    await session.flush()

    # Add creator as owner
    membership = Membership(
        group_id=group.id,
        user_id=owner_id,
        role=MembershipRole.OWNER,
    )
    session.add(membership)
    await session.commit()
    await session.refresh(group)

    return group

