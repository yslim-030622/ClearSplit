import uuid
from datetime import datetime

from sqlalchemy import Integer, String, Text, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.activity_log import ActivityLog
    from app.models.expense import Expense
    from app.models.membership import Membership
    from app.models.settlement import SettlementBatch


class Group(Base):
    """Group model for expense groups."""

    __tablename__ = "groups"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    name: Mapped[str] = mapped_column(Text(), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, server_default="USD")
    version: Mapped[int] = mapped_column(Integer(), nullable=False, server_default="1")
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

    # Relationships
    memberships: Mapped[list["Membership"]] = relationship(
        back_populates="group",
        cascade="all, delete-orphan",
        lazy="selectin",  # Async-friendly eager loading
    )
    expenses: Mapped[list["Expense"]] = relationship(
        back_populates="group",
        cascade="all, delete-orphan",
        lazy="selectin",  # Async-friendly eager loading
    )
    settlement_batches: Mapped[list["SettlementBatch"]] = relationship(
        back_populates="group",
        cascade="all, delete-orphan",
        lazy="selectin",  # Async-friendly eager loading
    )
    activity_logs: Mapped[list["ActivityLog"]] = relationship(
        back_populates="group",
        cascade="all, delete-orphan",
        lazy="selectin",  # Async-friendly eager loading
    )

