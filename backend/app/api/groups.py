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
from app.schemas.membership import (
    AddMemberRequest,
    MemberPreviewRequest,
    MemberPreviewResponse,
    MembershipRead,
)
from app.schemas.user import UserRead
from app.services.group import (
    create_group_with_owner,
    get_group_by_id,
    get_user_groups,
    require_owner_role,
)
from app.services.membership import (
    add_member_to_group,
    find_user_by_email,
    find_user_by_username,
    get_group_members,
)

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
        List of groups with user's membership ID
    """
    from sqlalchemy import select
    
    groups = await get_user_groups(session, current_user.id)
    result_groups = []
    
    for group in groups:
        # Find user's membership in this group
        membership_result = await session.execute(
            select(Membership).where(
                Membership.group_id == group.id,
                Membership.user_id == current_user.id
            )
        )
        membership = membership_result.scalar_one_or_none()
        
        group_dict = GroupRead.model_validate(group).model_dump()
        group_dict['user_membership_id'] = membership.id if membership else None
        result_groups.append(GroupRead.model_validate(group_dict))
    
    return result_groups


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


@router.post("/{group_id}/members/preview", response_model=MemberPreviewResponse)
async def preview_member_invite(
    group_id: UUID,
    request: MemberPreviewRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> MemberPreviewResponse:
    """Preview member invite by checking if user exists and membership status.
    
    Only group owners can preview invites. Rate limiting recommended
    to prevent email enumeration attacks.
    
    Args:
        group_id: Group UUID
        request: Preview request with email
        current_user: Current authenticated user
        session: Database session
        
    Returns:
        Preview response indicating if user exists and membership status
        
    Raises:
        HTTPException: If user is not owner or group not found
    """
    # Verify user is owner (only owners can invite)
    await require_owner_role(session, group_id, current_user.id)
    
    # Verify group exists
    await get_group_by_id(session, group_id, current_user.id)
    
    # Find user by username or email
    if request.username:
        user = await find_user_by_username(session, request.username)
    elif request.email:
        user = await find_user_by_email(session, request.email)
    else:
        # This shouldn't happen due to validation, but handle it
        return MemberPreviewResponse(found=False)
    
    if not user:
        # User not found - return minimal response
        return MemberPreviewResponse(found=False)
    
    # Check if already a member
    from sqlalchemy import select
    result = await session.execute(
        select(Membership).where(
            Membership.group_id == group_id,
            Membership.user_id == user.id
        )
    )
    existing_membership = result.scalar_one_or_none()
    
    if existing_membership:
        # Already a member
        return MemberPreviewResponse(
            found=True,
            already_member=True,
            user=UserRead.model_validate(user),
            membership_id=existing_membership.id,
            role=existing_membership.role,
        )
    
    # User exists but not a member yet
    return MemberPreviewResponse(
        found=True,
        already_member=False,
        user=UserRead.model_validate(user),
    )


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
        username=request.username,
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

