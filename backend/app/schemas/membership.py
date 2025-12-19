"""Membership schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import Field, model_validator

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

    Can add by email (if user exists) or by user_id.
    """

    email: str | None = Field(None, description="User email to add (if user exists)")
    user_id: UUID | None = Field(None, description="User ID to add")
    role: MembershipRole = Field(
        default=MembershipRole.MEMBER,
        description="Membership role (owner, member, viewer)",
    )

    def model_post_init(self, __context) -> None:
        """Validate that either email or user_id is provided."""
        if not self.email and not self.user_id:
            raise ValueError("Either email or user_id must be provided")
        if self.email and self.user_id:
            raise ValueError("Provide either email or user_id, not both")

