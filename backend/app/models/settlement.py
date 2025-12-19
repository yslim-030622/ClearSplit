import enum
import uuid
from datetime import datetime

from sqlalchemy import BigInteger, CheckConstraint, Enum as SQLEnum, ForeignKey, Integer, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.group import Group
    from app.models.membership import Membership


class SettlementStatus(str, enum.Enum):
    """Settlement status enum."""

    SUGGESTED = "suggested"
    PAID = "paid"
    VOIDED = "voided"


class SettlementBatch(Base):
    """Settlement batch model for immutable settlement snapshots."""

    __tablename__ = "settlement_batches"

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
    status: Mapped[SettlementStatus] = mapped_column(
        SQLEnum(SettlementStatus, name="settlement_status"),
        server_default="'suggested'",
        nullable=False,
    )
    total_settlements: Mapped[int] = mapped_column(Integer(), nullable=False, server_default="0")
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
    voided_reason: Mapped[str | None] = mapped_column(Text(), nullable=True)

    __table_args__ = (
        UniqueConstraint("id", "group_id", name="uq_settlement_batches_group_id"),
    )

    # Relationships
    group: Mapped["Group"] = relationship(back_populates="settlement_batches")
    settlements: Mapped[list["Settlement"]] = relationship(
        back_populates="batch",
        cascade="all, delete-orphan",
    )


class Settlement(Base):
    """Settlement model for individual transfer instructions."""

    __tablename__ = "settlements"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="uuid_generate_v4()",
    )
    batch_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    from_membership: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    to_membership: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    amount_cents: Mapped[int] = mapped_column(BigInteger(), nullable=False)
    status: Mapped[SettlementStatus] = mapped_column(
        SQLEnum(SettlementStatus, name="settlement_status"),
        server_default="'suggested'",
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        CheckConstraint("amount_cents > 0", name="chk_settlements_amount_positive"),
        CheckConstraint("from_membership <> to_membership", name="chk_settlements_from_to_diff"),
        # Composite FKs are handled at DB level via deferred constraints
    )

    # Relationships
    batch: Mapped["SettlementBatch"] = relationship(back_populates="settlements")
    from_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[from_membership],
    )
    to_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[to_membership],
    )

