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

