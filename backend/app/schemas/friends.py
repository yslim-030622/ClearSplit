"""Friends feature schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.models.friendship import FriendshipStatus
from app.schemas.base import BaseSchema


class FriendRequestCreate(BaseSchema):
    """Request payload for creating a friend request."""

    to_user_id: UUID | None = Field(
        None,
        description="Target user ID",
    )
    identifier: str | None = Field(
        None,
        description="Target user identifier (username or email)",
        max_length=255,
    )

    def model_post_init(self, __context) -> None:
        if self.identifier is not None:
            self.identifier = self.identifier.strip()
            if not self.identifier:
                self.identifier = None

        provided = int(self.to_user_id is not None) + int(self.identifier is not None)
        if provided != 1:
            raise ValueError("Provide exactly one of to_user_id or identifier")


class FriendUserOut(BaseSchema):
    """Minimal user payload exposed in friends APIs."""

    id: UUID
    username: str
    first_name: str
    last_name: str


class FriendshipOut(BaseSchema):
    """Friendship response payload."""

    id: UUID
    requested_by_user_id: UUID
    status: FriendshipStatus
    created_at: datetime
    updated_at: datetime
    friend: FriendUserOut
