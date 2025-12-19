import enum
import uuid
from datetime import datetime

from sqlalchemy import Enum as SQLEnum, ForeignKey, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.group import Group
    from app.models.user import User


class MembershipRole(str, enum.Enum):
    """Membership role enum."""

    OWNER = "owner"
    MEMBER = "member"
    VIEWER = "viewer"


class Membership(Base):
    """Membership model linking users to groups with roles."""

    __tablename__ = "memberships"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[MembershipRole] = mapped_column(
        SQLEnum(MembershipRole, name="membership_role"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Unique constraints (composite)
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_memberships_group_user"),
        UniqueConstraint("group_id", "id", name="uq_memberships_group_id"),
    )

    # Relationships
    group: Mapped["Group"] = relationship(back_populates="memberships")
    user: Mapped["User"] = relationship()

