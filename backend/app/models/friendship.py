import enum
import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    Enum as SQLEnum,
    ForeignKey,
    Index,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

if TYPE_CHECKING:
    from app.models.user import User


class FriendshipStatus(str, enum.Enum):
    """Friendship lifecycle status."""

    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"


class Friendship(Base):
    """Normalized friendship edge between two users."""

    __tablename__ = "friendships"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="gen_random_uuid()",
    )
    user_low_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_high_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    requested_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[FriendshipStatus] = mapped_column(
        SQLEnum(
            FriendshipStatus,
            name="friendship_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        nullable=False,
        server_default="'pending'",
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("user_low_id", "user_high_id", name="uq_friendships_user_pair"),
        CheckConstraint("user_low_id <> user_high_id", name="chk_friendships_distinct_users"),
        CheckConstraint(
            "requested_by_user_id = user_low_id OR requested_by_user_id = user_high_id",
            name="chk_friendships_requested_by_participant",
        ),
        Index("idx_friendships_status_user_low", "status", "user_low_id"),
        Index("idx_friendships_status_user_high", "status", "user_high_id"),
    )

    user_low: Mapped["User"] = relationship(foreign_keys=[user_low_id])
    user_high: Mapped["User"] = relationship(foreign_keys=[user_high_id])
    requested_by_user: Mapped["User"] = relationship(foreign_keys=[requested_by_user_id])
