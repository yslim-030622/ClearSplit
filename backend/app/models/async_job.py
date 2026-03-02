"""Async background job model."""

import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Index, String, Text, text, func
from sqlalchemy.dialects.postgresql import JSONB, TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class AsyncJob(Base):
    """Tracks async background job lifecycle."""

    __tablename__ = "async_jobs"
    __table_args__ = (
        # Concurrency-safe: only one active (queued/running) job per receipt per type
        Index(
            "ix_async_jobs_active_receipt",
            "job_type",
            "receipt_upload_id",
            unique=True,
            postgresql_where=text("status IN ('queued', 'running')"),
        ),
        Index("ix_async_jobs_created_by", "created_by_user_id"),
        Index("ix_async_jobs_receipt_upload", "receipt_upload_id"),
        Index("ix_async_jobs_status", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default=func.gen_random_uuid(),
    )
    job_type: Mapped[str] = mapped_column(String(50), nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default="queued"
    )
    attempt: Mapped[int] = mapped_column(default=0, server_default="0")
    max_attempts: Mapped[int] = mapped_column(default=3, server_default="3")

    receipt_upload_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("receipt_uploads.id", ondelete="CASCADE"),
        nullable=True,
    )
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP(timezone=True), server_default=func.now(), nullable=False
    )
    started_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True), nullable=True
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True), nullable=True
    )
    last_error: Mapped[str | None] = mapped_column(Text(), nullable=True)
    result_summary: Mapped[dict | None] = mapped_column(JSONB(), nullable=True)
