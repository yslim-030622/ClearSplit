"""Shopping service layer for business logic."""

import os
import uuid
from datetime import date
from pathlib import Path
from typing import BinaryIO
from uuid import UUID

from fastapi import HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.group import Group
from app.models.membership import Membership
from app.models.receipt_upload import ReceiptUpload
from app.models.shopping_item import ShoppingItem
from app.models.shopping_item_split import ShoppingItemSplit
from app.models.shopping_session import ShoppingSession
from app.models.shopping_session_participant import ShoppingSessionParticipant


# ============================================================================
# Helper functions
# ============================================================================


def calculate_equal_splits(total_cents: int, num_sharers: int) -> list[int]:
    """Calculate equal splits with deterministic remainder distribution.

    Args:
        total_cents: Total amount in cents
        num_sharers: Number of people to split among

    Returns:
        List of share amounts in cents for each person

    Example:
        total_cents=1000, num_sharers=3
        Returns: [334, 333, 333] (first person gets remainder)
    """
    if num_sharers <= 0:
        raise ValueError("Number of sharers must be positive")

    base_share = total_cents // num_sharers
    remainder = total_cents % num_sharers

    # First 'remainder' people get base_share + 1, rest get base_share
    splits = [base_share + 1] * remainder + [base_share] * (num_sharers - remainder)
    return splits


async def validate_memberships_in_group(
    session: AsyncSession, group_id: UUID, membership_ids: list[UUID]
) -> list[Membership]:
    """Validate that all membership IDs belong to the group.

    Args:
        session: Database session
        group_id: Group UUID
        membership_ids: List of membership UUIDs to validate

    Returns:
        List of validated memberships (sorted by UUID for determinism)

    Raises:
        HTTPException: If any membership is not found or not in group
    """
    result = await session.execute(
        select(Membership).where(
            Membership.id.in_(membership_ids), Membership.group_id == group_id
        )
    )
    memberships = list(result.scalars().all())

    if len(memberships) != len(membership_ids):
        found_ids = {m.id for m in memberships}
        missing_ids = set(membership_ids) - found_ids
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Memberships not found in group: {missing_ids}",
        )

    # Sort by UUID string for deterministic ordering
    memberships.sort(key=lambda m: str(m.id))
    return memberships


# ============================================================================
# Storage abstraction (local filesystem for MVP)
# ============================================================================


class ReceiptStorage:
    """Simple local filesystem storage for receipt images."""

    def __init__(self, base_path: str = "/tmp/clearsplit_receipts"):
        """Initialize storage with base path."""
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

    async def save_receipt(self, file: UploadFile, session_id: UUID) -> tuple[str, str]:
        """Save receipt file to storage.

        Args:
            file: Uploaded file
            session_id: Session UUID

        Returns:
            Tuple of (storage_key, content_type)

        Raises:
            HTTPException: If file type is invalid or save fails
        """
        # Validate content type
        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid file type. Expected image/*, got {file.content_type}",
            )

        # Generate unique storage key
        file_ext = self._get_file_extension(file.filename or "receipt.jpg")
        storage_key = f"{session_id}/{uuid.uuid4()}{file_ext}"
        file_path = self.base_path / storage_key

        # Ensure directory exists
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # Save file
        try:
            content = await file.read()
            file_path.write_bytes(content)
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to save receipt: {str(e)}",
            )

        return storage_key, file.content_type

    def _get_file_extension(self, filename: str) -> str:
        """Extract file extension from filename."""
        if "." in filename:
            return "." + filename.rsplit(".", 1)[1].lower()
        return ".jpg"

    def get_file_path(self, storage_key: str) -> Path:
        """Get full file path for a storage key."""
        return self.base_path / storage_key


# Global storage instance
receipt_storage = ReceiptStorage()


# ============================================================================
# Shopping Session operations
# ============================================================================


async def create_shopping_session(
    session: AsyncSession,
    group_id: UUID,
    title: str,
    paid_by_membership_id: UUID,
    shopping_date: date | None = None,
) -> ShoppingSession:
    """Create a shopping session.

    Args:
        session: Database session
        group_id: Group UUID
        title: Session title
        paid_by_membership_id: Membership ID of payer (must be in group)
        shopping_date: Optional date of shopping trip

    Returns:
        Created shopping session

    Raises:
        HTTPException: If group not found or payer not in group
    """
    # Validate group exists
    result = await session.execute(select(Group).where(Group.id == group_id))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Group {group_id} not found",
        )

    # Validate payer is a member of the group
    await validate_memberships_in_group(session, group_id, [paid_by_membership_id])

    # Create session
    shopping_session = ShoppingSession(
        group_id=group_id,
        title=title,
        shopping_date=shopping_date,
        currency="USD",  # Fixed for MVP
        paid_by_membership_id=paid_by_membership_id,
    )

    session.add(shopping_session)
    await session.flush()
    await session.refresh(shopping_session)

    return shopping_session


async def get_shopping_session(
    session: AsyncSession, session_id: UUID
) -> ShoppingSession:
    """Get shopping session by ID with all related data.

    Args:
        session: Database session
        session_id: Session UUID

    Returns:
        Shopping session with participants, receipts, and items

    Raises:
        HTTPException: If session not found
    """
    result = await session.execute(
        select(ShoppingSession)
        .where(ShoppingSession.id == session_id)
        .options(
            selectinload(ShoppingSession.participants),
            selectinload(ShoppingSession.receipts),
            selectinload(ShoppingSession.items).selectinload(ShoppingItem.splits),
        )
    )
    shopping_session = result.scalar_one_or_none()
    if not shopping_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shopping session {session_id} not found",
        )

    return shopping_session


async def list_shopping_sessions(
    session: AsyncSession, group_id: UUID
) -> list[ShoppingSession]:
    """List all shopping sessions for a group.

    Args:
        session: Database session
        group_id: Group UUID

    Returns:
        List of shopping sessions
    """
    result = await session.execute(
        select(ShoppingSession)
        .where(ShoppingSession.group_id == group_id)
        .order_by(ShoppingSession.created_at.desc())
        .options(
            selectinload(ShoppingSession.participants),
            selectinload(ShoppingSession.receipts),
            selectinload(ShoppingSession.items).selectinload(ShoppingItem.splits),
        )
    )
    return list(result.scalars().all())


async def set_session_participants(
    session: AsyncSession,
    shopping_session: ShoppingSession,
    participant_membership_ids: list[UUID],
    requester_membership_id: UUID,
) -> ShoppingSession:
    """Set/replace participants for a shopping session.

    Args:
        session: Database session
        shopping_session: Shopping session to update
        participant_membership_ids: List of membership IDs to set as participants
        requester_membership_id: Membership ID of requester (must be payer)

    Returns:
        Updated shopping session

    Raises:
        HTTPException: If requester is not payer or memberships invalid
    """
    # Verify requester is the payer
    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can set participants",
        )

    # Validate all participants are members of the group
    await validate_memberships_in_group(
        session, shopping_session.group_id, participant_membership_ids
    )

    # Remove existing participants
    await session.execute(
        select(ShoppingSessionParticipant).where(
            ShoppingSessionParticipant.session_id == shopping_session.id
        )
    )
    for participant in shopping_session.participants:
        await session.delete(participant)

    # Add new participants
    for membership_id in participant_membership_ids:
        participant = ShoppingSessionParticipant(
            session_id=shopping_session.id,
            membership_id=membership_id,
        )
        session.add(participant)

    await session.flush()
    await session.refresh(shopping_session)

    return shopping_session


# ============================================================================
# Receipt operations
# ============================================================================


async def upload_receipt(
    session: AsyncSession,
    shopping_session: ShoppingSession,
    file: UploadFile,
    requester_membership_id: UUID,
) -> ReceiptUpload:
    """Upload a receipt for a shopping session.

    Args:
        session: Database session
        shopping_session: Shopping session to add receipt to
        file: Uploaded file
        requester_membership_id: Membership ID of requester (must be payer)

    Returns:
        Created receipt upload

    Raises:
        HTTPException: If requester is not payer or upload fails
    """
    # Verify requester is the payer
    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can upload receipts",
        )

    # Save file to storage
    storage_key, content_type = await receipt_storage.save_receipt(
        file, shopping_session.id
    )

    # Create receipt record
    receipt = ReceiptUpload(
        session_id=shopping_session.id,
        storage_key=storage_key,
        content_type=content_type,
    )

    session.add(receipt)
    await session.flush()
    await session.refresh(receipt)

    return receipt


# ============================================================================
# Shopping Item operations
# ============================================================================


async def create_shopping_item(
    session: AsyncSession,
    shopping_session: ShoppingSession,
    name: str,
    quantity: int,
    total_cents: int,
    unit_price_cents: int | None,
    requester_membership_id: UUID,
) -> ShoppingItem:
    """Create a shopping item.

    Args:
        session: Database session
        shopping_session: Shopping session to add item to
        name: Item name
        quantity: Quantity
        total_cents: Total price in cents
        unit_price_cents: Optional unit price in cents
        requester_membership_id: Membership ID of requester (must be payer)

    Returns:
        Created shopping item

    Raises:
        HTTPException: If requester is not payer
    """
    # Verify requester is the payer
    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can add items",
        )

    # Create item
    item = ShoppingItem(
        session_id=shopping_session.id,
        name=name,
        quantity=quantity,
        total_cents=total_cents,
        unit_price_cents=unit_price_cents,
    )

    session.add(item)
    await session.flush()
    await session.refresh(item)

    return item


async def set_item_sharers(
    session: AsyncSession,
    item: ShoppingItem,
    sharer_membership_ids: list[UUID],
    requester_membership_id: UUID,
) -> list[ShoppingItemSplit]:
    """Set/replace sharers for a shopping item with equal split.

    Args:
        session: Database session
        item: Shopping item to set sharers for
        sharer_membership_ids: List of membership IDs who share this item
        requester_membership_id: Membership ID of requester (must be payer)

    Returns:
        List of created splits

    Raises:
        HTTPException: If requester is not payer or sharers not participants
    """
    # Get the shopping session
    result = await session.execute(
        select(ShoppingSession)
        .where(ShoppingSession.id == item.session_id)
        .options(selectinload(ShoppingSession.participants))
    )
    shopping_session = result.scalar_one_or_none()
    if not shopping_session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shopping session for item {item.id} not found",
        )

    # Verify requester is the payer
    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can set sharers",
        )

    # Verify all sharers are participants in the session
    participant_ids = {p.membership_id for p in shopping_session.participants}
    invalid_sharers = set(sharer_membership_ids) - participant_ids
    if invalid_sharers:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Sharers must be session participants. Invalid: {invalid_sharers}",
        )

    # Validate sharers exist and are in the group
    sharers = await validate_memberships_in_group(
        session, shopping_session.group_id, sharer_membership_ids
    )

    # Remove existing splits
    for split in item.splits:
        await session.delete(split)

    # Calculate equal splits (deterministic by sorted membership IDs)
    share_amounts = calculate_equal_splits(item.total_cents, len(sharers))

    # Create new splits
    new_splits = []
    for membership, share_cents in zip(sharers, share_amounts):
        split = ShoppingItemSplit(
            item_id=item.id,
            membership_id=membership.id,
            share_cents=share_cents,
        )
        session.add(split)
        new_splits.append(split)

    await session.flush()

    # Refresh all splits to get created_at timestamps
    for split in new_splits:
        await session.refresh(split)

    return new_splits


async def get_shopping_item(session: AsyncSession, item_id: UUID) -> ShoppingItem:
    """Get shopping item by ID with splits.

    Args:
        session: Database session
        item_id: Item UUID

    Returns:
        Shopping item with splits

    Raises:
        HTTPException: If item not found
    """
    result = await session.execute(
        select(ShoppingItem)
        .where(ShoppingItem.id == item_id)
        .options(selectinload(ShoppingItem.splits))
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shopping item {item_id} not found",
        )

    return item


# ============================================================================
# Authorization helpers
# ============================================================================


async def verify_user_is_group_member(
    session: AsyncSession, user_id: UUID, group_id: UUID
) -> Membership:
    """Verify user is a member of the group.

    Args:
        session: Database session
        user_id: User UUID
        group_id: Group UUID

    Returns:
        User's membership in the group

    Raises:
        HTTPException: If user is not a member
    """
    result = await session.execute(
        select(Membership).where(
            Membership.user_id == user_id, Membership.group_id == group_id
        )
    )
    membership = result.scalar_one_or_none()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )

    return membership

