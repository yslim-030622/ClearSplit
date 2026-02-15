"""Membership schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.models.membership import MembershipRole
from app.schemas.base import BaseSchema
from app.schemas.user import UserRead


class MembershipRead(BaseSchema):
    """Membership read schema."""

    id: UUID
    group_id: UUID
    user_id: UUID
    role: MembershipRole
    created_at: datetime
    # Optional: include user details if needed
    user: UserRead | None = None


class MembershipCreate(BaseSchema):
    """Membership creation schema."""

    user_id: UUID = Field(..., description="User ID to add to group")
    role: MembershipRole = Field(
        default=MembershipRole.MEMBER,
        description="Membership role (owner, member, viewer)",
    )


class MembershipUpdate(BaseSchema):
    """Membership update schema (role only, as per constraints)."""

    role: MembershipRole = Field(..., description="New membership role")


class AddMemberRequest(BaseSchema):
    """Add member to group request schema.

    Can add by username, email (if user exists), or by user_id.
    """

    username: str | None = Field(None, description="User username to add (if user exists)")
    email: str | None = Field(None, description="User email to add (if user exists)")
    user_id: UUID | None = Field(None, description="User ID to add")
    role: MembershipRole = Field(
        default=MembershipRole.MEMBER,
        description="Membership role (owner, member, viewer)",
    )

    def model_post_init(self, __context) -> None:
        """Validate that one of username, email, or user_id is provided."""
        provided = sum([bool(self.username), bool(self.email), bool(self.user_id)])
        if provided == 0:
            raise ValueError("Either username, email, or user_id must be provided")
        if provided > 1:
            raise ValueError("Provide only one of username, email, or user_id")


class MemberPreviewRequest(BaseSchema):
    """Preview member invite request.
    
    Can search by username (alphanumeric ID) or email.
    """

    username: str | None = Field(None, description="Username (alphanumeric ID) to check")
    email: str | None = Field(None, description="Email to check")

    def model_post_init(self, __context) -> None:
        """Validate that either username or email is provided."""
        if not self.username and not self.email:
            raise ValueError("Either username or email must be provided")
        if self.username and self.email:
            raise ValueError("Provide either username or email, not both")


class MemberPreviewResponse(BaseSchema):
    """Preview member invite response."""

    found: bool = Field(..., description="Whether user exists")
    already_member: bool | None = Field(
        None, description="Whether user is already a member (only if found=true)"
    )
    user: UserRead | None = Field(
        None, description="Minimal user info (only if found=true)"
    )
    membership_id: UUID | None = Field(
        None, description="Membership ID if already a member"
    )
    role: MembershipRole | None = Field(
        None, description="Current role if already a member"
    )
