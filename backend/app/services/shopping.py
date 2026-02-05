"""Shopping service layer for business logic."""

import os
import uuid
from datetime import date
from pathlib import Path
from typing import BinaryIO
from uuid import UUID

import boto3
from dotenv import load_dotenv
from fastapi import HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
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
    db: AsyncSession, group_id: UUID, membership_ids: list[UUID]
) -> list[Membership]:
    """Validate that all membership IDs belong to the group.

    Args:
        db: Database session
        group_id: Group UUID
        membership_ids: List of membership UUIDs to validate

    Returns:
        List of validated memberships (sorted by UUID for determinism)

    Raises:
        HTTPException: If any membership is not found or not in group
    """
    result = await db.execute(
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
# Storage abstraction (S3)
# ============================================================================

# Load .env file to make AWS credentials available to boto3
# This ensures AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from .env are in environment
env_path = Path(__file__).parent.parent.parent / ".env"
if env_path.exists():
    load_dotenv(env_path)


class ReceiptStorage:
    """S3 storage for receipt images."""

    def __init__(self):
        """Initialize S3 storage client."""
        self.settings = get_settings()
        self.s3_client = boto3.client("s3", region_name=self.settings.aws_region)

    async def save_receipt(self, file: UploadFile, session_id: UUID) -> tuple[str, str]:
        """Save receipt file to S3.

        Args:
            file: Uploaded file
            session_id: Session UUID

        Returns:
            Tuple of (storage_key, content_type)

        Raises:
            HTTPException: If file type is invalid, too large, or upload fails
        """
        # Validate content type
        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid file type. Expected image/*, got {file.content_type}",
            )

        # Read file content
        content = await file.read()

        # Validate file size
        if len(content) > self.settings.max_receipt_bytes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File too large. Maximum size is {self.settings.max_receipt_bytes} bytes",
            )

        # Generate unique storage key: {prefix}/{session_id}/{uuid}.{ext}
        file_ext = self._get_file_extension(file.filename or "receipt.jpg")
        storage_key = f"{self.settings.s3_prefix}/{session_id}/{uuid.uuid4()}{file_ext}"

        # Upload to S3
        try:
            self.s3_client.put_object(
                Bucket=self.settings.s3_bucket_name,
                Key=storage_key,
                Body=content,
                ContentType=file.content_type,
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to upload receipt to S3: {str(e)}",
            )

        return storage_key, file.content_type

    def create_presigned_get_url(self, storage_key: str) -> str:
        """Generate a presigned GET URL for downloading a receipt from S3.

        Args:
            storage_key: S3 object key (from ReceiptUpload.storage_key)

        Returns:
            Presigned URL string

        Raises:
            HTTPException: If URL generation fails
        """
        try:
            url = self.s3_client.generate_presigned_url(
                "get_object",
                Params={
                    "Bucket": self.settings.s3_bucket_name,
                    "Key": storage_key,
                },
                ExpiresIn=self.settings.s3_presigned_get_expire_seconds,
            )
            return url
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to generate download URL",
            )

    def delete_receipt(self, storage_key: str) -> None:
        """Delete a receipt object from S3."""
        try:
            self.s3_client.delete_object(
                Bucket=self.settings.s3_bucket_name,
                Key=storage_key,
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete receipt from S3",
            )

    def _get_file_extension(self, filename: str) -> str:
        """Extract file extension from filename."""
        if "." in filename:
            return "." + filename.rsplit(".", 1)[1].lower()
        return ".jpg"


# Global storage instance
receipt_storage = ReceiptStorage()


# ============================================================================
# Shopping Session operations
# ============================================================================


async def create_shopping_session(
    db: AsyncSession,
    group_id: UUID,
    title: str,
    paid_by_membership_id: UUID,
    shopping_date: date | None = None,
    total_amount: float | None = None,
) -> ShoppingSession:
    """Create a shopping session.

    Args:
        db: Database session
        group_id: Group UUID
        title: Session title
        paid_by_membership_id: Membership ID of payer (must be in group)
        shopping_date: Optional date of shopping trip
        total_amount: Optional total amount for quick splits without itemization

    Returns:
        Created shopping session

    Raises:
        HTTPException: If group not found or payer not in group
    """
    # Validate group exists
    result = await db.execute(select(Group).where(Group.id == group_id))
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Group {group_id} not found",
        )

    # Validate payer is a member of the group
    await validate_memberships_in_group(db, group_id, [paid_by_membership_id])

    # Create session
    shopping_session = ShoppingSession(
        group_id=group_id,
        title=title,
        shopping_date=shopping_date,
        total_amount=total_amount,
        currency="USD",  # Fixed for MVP
        paid_by_membership_id=paid_by_membership_id,
    )

    db.add(shopping_session)
    await db.flush()
    await db.refresh(shopping_session)

    return shopping_session


async def get_shopping_session(
    db: AsyncSession, session_id: UUID
) -> ShoppingSession:
    """Get shopping session by ID with all related data.

    Args:
        db: Database session
        session_id: Session UUID

    Returns:
        Shopping session with participants, receipts, and items

    Raises:
        HTTPException: If session not found
    """
    result = await db.execute(
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
    db: AsyncSession, group_id: UUID
) -> list[ShoppingSession]:
    """List all shopping sessions for a group.

    Args:
        db: Database session
        group_id: Group UUID

    Returns:
        List of shopping sessions
    """
    result = await db.execute(
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
    db: AsyncSession,
    shopping_session: ShoppingSession,
    participant_membership_ids: list[UUID],
    requester_membership_id: UUID,
) -> ShoppingSession:
    """Set/replace participants for a shopping session.

    Args:
        db: Database session
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
        db, shopping_session.group_id, participant_membership_ids
    )

    # Remove existing participants
    result = await db.execute(
        select(ShoppingSessionParticipant).where(
            ShoppingSessionParticipant.session_id == shopping_session.id
        )
    )
    existing_participants = result.scalars().all()
    for participant in existing_participants:
        await db.delete(participant)
    await db.flush()

    # Add new participants
    for membership_id in participant_membership_ids:
        participant = ShoppingSessionParticipant(
            session_id=shopping_session.id,
            membership_id=membership_id,
        )
        db.add(participant)

    await db.flush()
    await db.refresh(shopping_session)

    return shopping_session


# ============================================================================
# Receipt operations
# ============================================================================


async def upload_receipt(
    db: AsyncSession,
    shopping_session: ShoppingSession,
    file: UploadFile,
    requester_membership_id: UUID,
) -> ReceiptUpload:
    """Upload a receipt for a shopping session.

    Args:
        db: Database session
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

    db.add(receipt)
    await db.flush()
    await db.refresh(receipt)

    return receipt


async def get_receipt_upload(
    db: AsyncSession, receipt_id: UUID
) -> ReceiptUpload:
    """Get receipt upload by ID.

    Args:
        db: Database session
        receipt_id: Receipt upload UUID

    Returns:
        Receipt upload

    Raises:
        HTTPException: If receipt not found
    """
    result = await db.execute(
        select(ReceiptUpload).where(ReceiptUpload.id == receipt_id)
    )
    receipt = result.scalar_one_or_none()
    if not receipt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Receipt upload {receipt_id} not found",
        )
    return receipt


async def delete_receipt_upload(
    db: AsyncSession,
    receipt: ReceiptUpload,
    shopping_session: ShoppingSession,
    requester_membership_id: UUID,
) -> None:
    """Delete a receipt upload (S3 object + DB record).

    Only the payer can delete receipts.
    """
    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can delete receipts",
        )

    # Delete from S3 first
    receipt_storage.delete_receipt(receipt.storage_key)

    # Delete DB record
    await db.delete(receipt)
    await db.flush()


# ============================================================================
# Shopping Item operations
# ============================================================================


async def create_shopping_item(
    db: AsyncSession,
    shopping_session: ShoppingSession,
    name: str,
    quantity: int,
    total_cents: int,
    unit_price_cents: int | None,
    requester_membership_id: UUID,
) -> ShoppingItem:
    """Create a shopping item.

    Args:
        db: Database session
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

    db.add(item)
    await db.flush()
    await db.refresh(item)

    return item


async def set_item_sharers(
    db: AsyncSession,
    item: ShoppingItem,
    sharer_membership_ids: list[UUID],
    requester_membership_id: UUID,
) -> list[ShoppingItemSplit]:
    """Set/replace sharers for a shopping item with equal split.

    Args:
        db: Database session
        item: Shopping item to set sharers for
        sharer_membership_ids: List of membership IDs who share this item
        requester_membership_id: Membership ID of requester (must be payer)

    Returns:
        List of created splits

    Raises:
        HTTPException: If requester is not payer or sharers not participants
    """
    # Get the shopping session
    result = await db.execute(
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
        db, shopping_session.group_id, sharer_membership_ids
    )

    # Remove existing splits
    for split in item.splits:
        await db.delete(split)

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
        db.add(split)
        new_splits.append(split)

    await db.flush()

    # Refresh all splits to get created_at timestamps
    for split in new_splits:
        await db.refresh(split)

    return new_splits


async def get_shopping_item(db: AsyncSession, item_id: UUID) -> ShoppingItem:
    """Get shopping item by ID with splits.

    Args:
        db: Database session
        item_id: Item UUID

    Returns:
        Shopping item with splits

    Raises:
        HTTPException: If item not found
    """
    result = await db.execute(
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
    db: AsyncSession, user_id: UUID, group_id: UUID
) -> Membership:
    """Verify user is a member of the group.

    Args:
        db: Database session
        user_id: User UUID
        group_id: Group UUID

    Returns:
        User's membership in the group

    Raises:
        HTTPException: If user is not a member
    """
    result = await db.execute(
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
