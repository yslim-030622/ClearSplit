import enum
import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Enum as SQLEnum,
    ForeignKey,
    ForeignKeyConstraint,
    Integer,
    PrimaryKeyConstraint,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from typing import TYPE_CHECKING

from app.db import Base

if TYPE_CHECKING:
    from app.models.group import Group
    from app.models.membership import Membership
    from app.models.shopping_session import ShoppingSession


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
        SQLEnum(
            SettlementStatus,
            name="settlement_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
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
        SQLEnum(
            SettlementStatus,
            name="settlement_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
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
        ForeignKeyConstraint(
            ["batch_id", "group_id"],
            ["settlement_batches.id", "settlement_batches.group_id"],
            ondelete="CASCADE",
            deferrable=True,
            initially="DEFERRED",
        ),
        ForeignKeyConstraint(
            ["group_id", "from_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
        ForeignKeyConstraint(
            ["group_id", "to_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
    )

    # Relationships
    batch: Mapped["SettlementBatch"] = relationship(back_populates="settlements")
    from_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[from_membership],
    )
    to_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[to_membership],
    )


class SettlementPaymentStatus(str, enum.Enum):
    """Persisted settlement payment status enum."""

    PENDING = "pending"
    CONFIRMED = "confirmed"
    VOIDED = "voided"


class SettlementPayment(Base):
    """Actual payment transfer record between two memberships."""

    __tablename__ = "settlement_payments"

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
    from_membership: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    to_membership: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    amount_cents: Mapped[int] = mapped_column(BigInteger(), nullable=False)
    status: Mapped[SettlementPaymentStatus] = mapped_column(
        SQLEnum(
            SettlementPaymentStatus,
            name="settlement_payment_status",
            values_callable=lambda enum_cls: [e.value for e in enum_cls],
        ),
        server_default="'pending'",
        nullable=False,
    )
    note: Mapped[str | None] = mapped_column(Text(), nullable=True)
    sent_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )
    confirmed_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("id", "group_id", name="uq_settlement_payments_group_id"),
        CheckConstraint("amount_cents > 0", name="chk_settlement_payments_amount_positive"),
        CheckConstraint("from_membership <> to_membership", name="chk_settlement_payments_from_to_diff"),
        ForeignKeyConstraint(
            ["group_id", "from_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
        ForeignKeyConstraint(
            ["group_id", "to_membership"],
            ["memberships.group_id", "memberships.id"],
            ondelete="RESTRICT",
            deferrable=True,
            initially="DEFERRED",
        ),
    )

    group: Mapped["Group"] = relationship()
    from_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[from_membership],
    )
    to_membership_rel: Mapped["Membership"] = relationship(
        foreign_keys=[to_membership],
    )
    session_links: Mapped[list["SettlementPaymentSession"]] = relationship(
        back_populates="payment",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class SettlementPaymentSession(Base):
    """Session coverage mapping for settlement payments."""

    __tablename__ = "settlement_payment_sessions"

    payment_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        nullable=False,
    )

    __table_args__ = (
        PrimaryKeyConstraint("payment_id", "session_id", name="pk_settlement_payment_sessions"),
        ForeignKeyConstraint(
            ["payment_id"],
            ["settlement_payments.id"],
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["session_id"],
            ["shopping_sessions.id"],
            ondelete="CASCADE",
        ),
    )

    payment: Mapped["SettlementPayment"] = relationship(back_populates="session_links")
    session: Mapped["ShoppingSession"] = relationship()
