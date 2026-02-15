"""Friends service layer for friendship business rules."""

from dataclasses import dataclass
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import case, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.identity import normalize_identifier
from app.models.friendship import Friendship, FriendshipStatus
from app.models.user import User


@dataclass
class FriendshipView:
    """Friendship row paired with the other user."""

    friendship: Friendship
    friend: User


def normalize_pair(a: UUID, b: UUID) -> tuple[UUID, UUID]:
    """Normalize a user pair to stable (low, high) ordering."""
    if str(a) <= str(b):
        return a, b
    return b, a


async def _get_user_or_404(session: AsyncSession, user_id: UUID) -> User:
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return user


async def _resolve_target_user(
    session: AsyncSession,
    *,
    to_user_id: UUID | None = None,
    identifier: str | None = None,
) -> User:
    if to_user_id is not None:
        return await _get_user_or_404(session, to_user_id)

    normalized = normalize_identifier(identifier or "")
    if not normalized:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide either to_user_id or identifier",
        )

    parsed_uuid: UUID | None = None
    try:
        parsed_uuid = UUID(normalized)
    except ValueError:
        parsed_uuid = None

    if parsed_uuid is not None:
        result = await session.execute(select(User).where(User.id == parsed_uuid))
        user = result.scalar_one_or_none()
        if user:
            return user

    result = await session.execute(
        select(User).where(
            or_(
                func.lower(User.username) == normalized,
                func.lower(User.email) == normalized,
            )
        )
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return user


async def _get_friendship_or_404(
    session: AsyncSession,
    *,
    friendship_id: UUID,
) -> Friendship:
    result = await session.execute(
        select(Friendship).where(Friendship.id == friendship_id)
    )
    friendship = result.scalar_one_or_none()
    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friendship not found",
        )
    return friendship


def _require_friendship_participant(friendship: Friendship, user_id: UUID) -> None:
    if user_id not in {friendship.user_low_id, friendship.user_high_id}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not part of this friendship",
        )


def _friend_user_id(friendship: Friendship, current_user_id: UUID) -> UUID:
    if current_user_id == friendship.user_low_id:
        return friendship.user_high_id
    if current_user_id == friendship.user_high_id:
        return friendship.user_low_id
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="You are not part of this friendship",
    )


async def _build_view(
    session: AsyncSession,
    *,
    friendship: Friendship,
    current_user_id: UUID,
) -> FriendshipView:
    friend = await _get_user_or_404(session, _friend_user_id(friendship, current_user_id))
    return FriendshipView(friendship=friendship, friend=friend)


async def _flush_or_conflict(session: AsyncSession, detail: str) -> None:
    try:
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=detail,
        ) from exc


async def send_friend_request(
    session: AsyncSession,
    *,
    current_user: User,
    to_user_id: UUID | None = None,
    identifier: str | None = None,
) -> FriendshipView:
    """Send a friend request with normalized-pair invariants.

    Policy decisions:
    - Reverse pending request auto-accepts immediately.
    - Declined friendship can be re-requested (status reset to pending).
    """
    to_user = await _resolve_target_user(
        session,
        to_user_id=to_user_id,
        identifier=identifier,
    )

    if to_user.id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot send a friend request to yourself",
        )

    user_low_id, user_high_id = normalize_pair(current_user.id, to_user.id)

    existing_result = await session.execute(
        select(Friendship)
        .where(
            Friendship.user_low_id == user_low_id,
            Friendship.user_high_id == user_high_id,
        )
        .with_for_update()
    )
    friendship = existing_result.scalar_one_or_none()

    if not friendship:
        friendship = Friendship(
            user_low_id=user_low_id,
            user_high_id=user_high_id,
            requested_by_user_id=current_user.id,
            status=FriendshipStatus.PENDING,
        )
        session.add(friendship)
        await _flush_or_conflict(session, "Friend request already exists")
        return FriendshipView(friendship=friendship, friend=to_user)

    if friendship.status == FriendshipStatus.ACCEPTED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Users are already friends",
        )

    if friendship.status == FriendshipStatus.PENDING:
        if friendship.requested_by_user_id == current_user.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Friend request already sent",
            )
        friendship.status = FriendshipStatus.ACCEPTED
        await _flush_or_conflict(session, "Failed to update friendship status")
        return FriendshipView(friendship=friendship, friend=to_user)

    friendship.status = FriendshipStatus.PENDING
    friendship.requested_by_user_id = current_user.id
    await _flush_or_conflict(session, "Failed to update friendship status")
    return FriendshipView(friendship=friendship, friend=to_user)


async def accept_friend_request(
    session: AsyncSession,
    *,
    current_user: User,
    friendship_id: UUID,
) -> FriendshipView:
    """Accept a pending friend request. Only the receiver can accept."""
    friendship = await _get_friendship_or_404(session, friendship_id=friendship_id)
    _require_friendship_participant(friendship, current_user.id)

    if friendship.status != FriendshipStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only pending friend requests can be accepted",
        )
    if friendship.requested_by_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the request receiver can accept",
        )

    friendship.status = FriendshipStatus.ACCEPTED
    await _flush_or_conflict(session, "Failed to update friendship status")
    return await _build_view(
        session,
        friendship=friendship,
        current_user_id=current_user.id,
    )


async def decline_friend_request(
    session: AsyncSession,
    *,
    current_user: User,
    friendship_id: UUID,
) -> FriendshipView:
    """Decline a pending friend request. Only the receiver can decline."""
    friendship = await _get_friendship_or_404(session, friendship_id=friendship_id)
    _require_friendship_participant(friendship, current_user.id)

    if friendship.status != FriendshipStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only pending friend requests can be declined",
        )
    if friendship.requested_by_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the request receiver can decline",
        )

    friendship.status = FriendshipStatus.DECLINED
    await _flush_or_conflict(session, "Failed to update friendship status")
    return await _build_view(
        session,
        friendship=friendship,
        current_user_id=current_user.id,
    )


async def list_friends(
    session: AsyncSession,
    *,
    current_user: User,
    q: str | None = None,
) -> list[FriendshipView]:
    """List accepted friendships for current user, optionally filtered by query."""
    other_user_id = case(
        (Friendship.user_low_id == current_user.id, Friendship.user_high_id),
        else_=Friendship.user_low_id,
    )

    stmt = (
        select(Friendship, User)
        .join(User, User.id == other_user_id)
        .where(
            or_(
                Friendship.user_low_id == current_user.id,
                Friendship.user_high_id == current_user.id,
            ),
            Friendship.status == FriendshipStatus.ACCEPTED,
        )
    )

    if q:
        query = q.strip()
        if query:
            pattern = f"%{query}%"
            stmt = stmt.where(
                or_(
                    User.username.ilike(pattern),
                    User.first_name.ilike(pattern),
                    User.last_name.ilike(pattern),
                )
            )

    stmt = stmt.order_by(func.lower(User.username).asc(), Friendship.created_at.asc())
    result = await session.execute(stmt)

    return [
        FriendshipView(friendship=friendship, friend=friend)
        for friendship, friend in result.all()
    ]


async def list_incoming_friend_requests(
    session: AsyncSession,
    *,
    current_user: User,
) -> list[FriendshipView]:
    """List pending friend requests sent to the current user."""
    other_user_id = case(
        (Friendship.user_low_id == current_user.id, Friendship.user_high_id),
        else_=Friendship.user_low_id,
    )

    stmt = (
        select(Friendship, User)
        .join(User, User.id == other_user_id)
        .where(
            or_(
                Friendship.user_low_id == current_user.id,
                Friendship.user_high_id == current_user.id,
            ),
            Friendship.status == FriendshipStatus.PENDING,
            Friendship.requested_by_user_id != current_user.id,
        )
    )
    stmt = stmt.order_by(Friendship.created_at.desc(), func.lower(User.username).asc())
    result = await session.execute(stmt)

    return [
        FriendshipView(friendship=friendship, friend=friend)
        for friendship, friend in result.all()
    ]


async def list_outgoing_friend_requests(
    session: AsyncSession,
    *,
    current_user: User,
) -> list[FriendshipView]:
    """List pending friend requests sent by the current user."""
    other_user_id = case(
        (Friendship.user_low_id == current_user.id, Friendship.user_high_id),
        else_=Friendship.user_low_id,
    )

    stmt = (
        select(Friendship, User)
        .join(User, User.id == other_user_id)
        .where(
            or_(
                Friendship.user_low_id == current_user.id,
                Friendship.user_high_id == current_user.id,
            ),
            Friendship.status == FriendshipStatus.PENDING,
            Friendship.requested_by_user_id == current_user.id,
        )
        .order_by(Friendship.created_at.desc(), func.lower(User.username).asc())
    )
    result = await session.execute(stmt)

    return [
        FriendshipView(friendship=friendship, friend=friend)
        for friendship, friend in result.all()
    ]


async def remove_friendship(
    session: AsyncSession,
    *,
    current_user: User,
    friendship_id: UUID,
) -> FriendshipView:
    """Delete a friendship edge (unfriend/cancel/remove)."""
    friendship = await _get_friendship_or_404(session, friendship_id=friendship_id)
    _require_friendship_participant(friendship, current_user.id)
    view = await _build_view(
        session,
        friendship=friendship,
        current_user_id=current_user.id,
    )
    await session.delete(friendship)
    await session.flush()
    return view
