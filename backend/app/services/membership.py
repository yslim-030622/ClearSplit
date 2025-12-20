"""Membership service layer for business logic."""

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.membership import Membership, MembershipRole
from app.models.user import User


async def find_user_by_email(
    session: AsyncSession, email: str
) -> User | None:
    """Find user by email.

    Args:
        session: Database session
        email: User email

    Returns:
        User if found, None otherwise
    """
    result = await session.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def add_member_to_group(
    session: AsyncSession,
    group_id: UUID,
    user_id: UUID | None = None,
    email: str | None = None,
    role: MembershipRole = MembershipRole.MEMBER,
) -> Membership:
    """Add a member to a group.

    Args:
        session: Database session
        group_id: Group UUID
        user_id: User UUID (if provided)
        email: User email (if user_id not provided)
        role: Membership role

    Returns:
        Created membership

    Raises:
        HTTPException: If user not found, already a member, or invalid input
    """
    # Find user
    if user_id:
        result = await session.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )
    elif email:
        user = await find_user_by_email(session, email)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User with email {email} not found",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Either user_id or email must be provided",
        )

    # Check if already a member
    existing = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id, Membership.user_id == user.id
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User is already a member of this group",
        )

    # Create membership
    membership = Membership(
        group_id=group_id,
        user_id=user.id,
        role=role,
    )
    session.add(membership)
    await session.commit()
    await session.refresh(membership, attribute_names=["user"])

    return membership


async def get_group_members(
    session: AsyncSession, group_id: UUID
) -> list[Membership]:
    """Get all members of a group.

    Args:
        session: Database session
        group_id: Group UUID

    Returns:
        List of memberships
    """
    result = await session.execute(
        select(Membership)
        .options(selectinload(Membership.user))
        .where(Membership.group_id == group_id)
        .order_by(Membership.created_at.asc())
    )
    return list(result.scalars().all())
