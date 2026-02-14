"""Friends API routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.user import User
from app.schemas.friends import FriendRequestCreate, FriendshipOut, FriendUserOut
from app.services.friends import (
    FriendshipView,
    accept_friend_request,
    decline_friend_request,
    list_friends,
    list_incoming_friend_requests,
    list_outgoing_friend_requests,
    remove_friendship,
    send_friend_request,
)

router = APIRouter(tags=["friends"])


def _serialize_friendship(view: FriendshipView) -> FriendshipOut:
    return FriendshipOut(
        id=view.friendship.id,
        requested_by_user_id=view.friendship.requested_by_user_id,
        status=view.friendship.status,
        created_at=view.friendship.created_at,
        updated_at=view.friendship.updated_at,
        friend=FriendUserOut.model_validate(view.friend),
    )


@router.post(
    "/friends/requests",
    response_model=FriendshipOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_friend_request(
    request: FriendRequestCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> FriendshipOut:
    view = await send_friend_request(
        session,
        current_user=current_user,
        to_user_id=request.to_user_id,
        identifier=request.identifier,
    )
    await session.commit()
    return _serialize_friendship(view)


@router.post(
    "/friends/requests/{friendship_id}/accept",
    response_model=FriendshipOut,
)
async def accept_request(
    friendship_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> FriendshipOut:
    view = await accept_friend_request(
        session,
        current_user=current_user,
        friendship_id=friendship_id,
    )
    await session.commit()
    return _serialize_friendship(view)


@router.post(
    "/friends/requests/{friendship_id}/decline",
    response_model=FriendshipOut,
)
async def decline_request(
    friendship_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> FriendshipOut:
    view = await decline_friend_request(
        session,
        current_user=current_user,
        friendship_id=friendship_id,
    )
    await session.commit()
    return _serialize_friendship(view)


@router.get("/friends", response_model=list[FriendshipOut])
async def get_friends(
    q: str | None = Query(default=None, max_length=100),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[FriendshipOut]:
    views = await list_friends(
        session,
        current_user=current_user,
        q=q,
    )
    return [_serialize_friendship(view) for view in views]


@router.get("/friends/requests/incoming", response_model=list[FriendshipOut])
async def get_incoming_friend_requests(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[FriendshipOut]:
    views = await list_incoming_friend_requests(
        session,
        current_user=current_user,
    )
    return [_serialize_friendship(view) for view in views]


@router.get("/friends/requests/outgoing", response_model=list[FriendshipOut])
async def get_outgoing_friend_requests(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[FriendshipOut]:
    views = await list_outgoing_friend_requests(
        session,
        current_user=current_user,
    )
    return [_serialize_friendship(view) for view in views]


@router.delete(
    "/friends/{friendship_id}",
    response_model=FriendshipOut,
)
async def delete_friendship(
    friendship_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> FriendshipOut:
    view = await remove_friendship(
        session,
        current_user=current_user,
        friendship_id=friendship_id,
    )
    await session.commit()
    return _serialize_friendship(view)
