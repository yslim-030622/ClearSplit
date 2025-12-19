"""Groups and memberships API routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.group import Group
from app.models.membership import Membership
from app.models.user import User
from app.schemas.group import GroupCreate, GroupRead
from app.schemas.membership import AddMemberRequest, MembershipRead
from app.services.group import (
    create_group_with_owner,
    get_group_by_id,
    get_user_groups,
    require_owner_role,
)
from app.services.membership import add_member_to_group, get_group_members

router = APIRouter(prefix="/groups", tags=["groups"])


@router.post("", response_model=GroupRead, status_code=status.HTTP_201_CREATED)
async def create_group(
    request: GroupCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupRead:
    """Create a new group.

    The creator is automatically added as the owner.

    Args:
        request: Group creation request
        current_user: Current authenticated user
        session: Database session

    Returns:
        Created group
    """
    group = await create_group_with_owner(
        session, request.name, request.currency, current_user.id
    )
    return GroupRead.model_validate(group)


@router.get("", response_model=list[GroupRead])
async def list_my_groups(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[GroupRead]:
    """List all groups where the current user is a member.

    Args:
        current_user: Current authenticated user
        session: Database session

    Returns:
        List of groups
    """
    groups = await get_user_groups(session, current_user.id)
    return [GroupRead.model_validate(group) for group in groups]


@router.get("/{group_id}", response_model=GroupRead)
async def get_group(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> GroupRead:
    """Get a specific group by ID.

    User must be a member of the group.

    Args:
        group_id: Group UUID
        current_user: Current authenticated user
        session: Database session

    Returns:
        Group details

    Raises:
        HTTPException: If group not found or user is not a member
    """
    group = await get_group_by_id(session, group_id, current_user.id)
    return GroupRead.model_validate(group)


@router.post(
    "/{group_id}/members",
    response_model=MembershipRead,
    status_code=status.HTTP_201_CREATED,
)
async def add_member(
    group_id: UUID,
    request: AddMemberRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> MembershipRead:
    """Add a member to a group.

    Only group owners can add members.
    Can add by email (if user exists) or by user_id.

    Args:
        group_id: Group UUID
        request: Add member request (email or user_id)
        current_user: Current authenticated user
        session: Database session

    Returns:
        Created membership

    Raises:
        HTTPException: If user is not owner, user not found, or already a member
    """
    # Verify user is owner
    await require_owner_role(session, group_id, current_user.id)

    # Verify group exists
    await get_group_by_id(session, group_id, current_user.id)

    # Add member
    membership = await add_member_to_group(
        session,
        group_id=group_id,
        user_id=request.user_id,
        email=request.email,
        role=request.role,
    )

    return MembershipRead.model_validate(membership)


@router.get("/{group_id}/members", response_model=list[MembershipRead])
async def list_members(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[MembershipRead]:
    """List all members of a group.

    User must be a member of the group.

    Args:
        group_id: Group UUID
        current_user: Current authenticated user
        session: Database session

    Returns:
        List of memberships

    Raises:
        HTTPException: If group not found or user is not a member
    """
    # Verify user is member and group exists
    await get_group_by_id(session, group_id, current_user.id)

    # Get members
    memberships = await get_group_members(session, group_id)
    return [MembershipRead.model_validate(m) for m in memberships]

