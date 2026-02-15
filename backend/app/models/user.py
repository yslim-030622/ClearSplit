import uuid
from datetime import datetime

from sqlalchemy import Index, Text, func
from sqlalchemy.dialects.postgresql import TIMESTAMP, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class User(Base):
    """User model for authentication and user management."""

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        server_default="gen_random_uuid()",
    )
    username: Mapped[str] = mapped_column(Text(), unique=True, nullable=False)
    email: Mapped[str] = mapped_column(Text(), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(Text(), nullable=False)
    first_name: Mapped[str] = mapped_column(Text(), nullable=False)
    last_name: Mapped[str] = mapped_column(Text(), nullable=False)
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
        Index("uq_users_email_ci", func.lower(email), unique=True),
        Index("uq_users_username_ci", func.lower(username), unique=True),
    )
