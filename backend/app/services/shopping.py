"""Shopping service layer for business logic."""

from __future__ import annotations

import logging
import uuid
import warnings
from datetime import date, datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import TYPE_CHECKING
from uuid import UUID

import boto3
from dotenv import load_dotenv
from fastapi import HTTPException, UploadFile, status
from PIL import Image, UnidentifiedImageError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models.group import Group
from app.models.membership import Membership, MembershipRole
from app.models.receipt_upload import ReceiptUpload
from app.models.shopping_item import ShoppingItem
from app.models.shopping_item_split import ShoppingItemSplit
from app.models.shopping_session import ShoppingSession, ShoppingSessionStatus
from app.models.shopping_session_participant import ShoppingSessionParticipant

if TYPE_CHECKING:
    from app.models.receipt_extracted_item import ReceiptExtractedItem

logger = logging.getLogger(__name__)


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


def calculate_equal_splits_for_sharers(
    total_cents: int,
    sharer_membership_ids: list[UUID],
    payer_membership_id: UUID,
) -> dict[UUID, int]:
    """Compute per-sharer equal splits with payer-preferred remainder assignment.

    Remainder assignment order:
    1) payer first (if payer is among sharers)
    2) deterministic UUID-string sort for all others
    """

    if not sharer_membership_ids:
        raise ValueError("At least one sharer is required")

    base_share = total_cents // len(sharer_membership_ids)
    remainder = total_cents % len(sharer_membership_ids)
    share_map = {membership_id: base_share for membership_id in sharer_membership_ids}

    sorted_membership_ids = sorted(sharer_membership_ids, key=str)
    if payer_membership_id in share_map:
        remainder_order = [payer_membership_id] + [
            membership_id
            for membership_id in sorted_membership_ids
            if membership_id != payer_membership_id
        ]
    else:
        remainder_order = sorted_membership_ids

    for membership_id in remainder_order[:remainder]:
        share_map[membership_id] += 1
    return share_map


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


def _touch_session_after_financial_mutation(shopping_session: ShoppingSession) -> None:
    """Re-open a settled session if obligations change."""

    if shopping_session.status == ShoppingSessionStatus.SETTLED:
        shopping_session.status = ShoppingSessionStatus.ACTIVE
        shopping_session.settled_at = None


async def can_manage_item(
    db: AsyncSession,
    shopping_session: ShoppingSession,
    item: ShoppingItem,
    requester_membership_id: UUID,
) -> bool:
    """Return true when requester can edit/delete/sharer-manage an item."""

    if requester_membership_id == item.created_by_membership_id:
        return True
    if requester_membership_id == shopping_session.paid_by_membership_id:
        return True

    membership_result = await db.execute(
        select(Membership).where(
            Membership.id == requester_membership_id,
            Membership.group_id == shopping_session.group_id,
        )
    )
    requester_membership = membership_result.scalar_one_or_none()
    if not requester_membership:
        return False
    return requester_membership.role == MembershipRole.OWNER


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
        # Pillow checks this global while decoding image headers.
        Image.MAX_IMAGE_PIXELS = self.settings.max_receipt_pixels
        self.s3_client = boto3.client("s3", region_name=self.settings.aws_region)
        self._allowed_formats: dict[str, tuple[str, str]] = {
            "JPEG": (".jpg", "image/jpeg"),
            "PNG": (".png", "image/png"),
            "WEBP": (".webp", "image/webp"),
            "GIF": (".gif", "image/gif"),
        }

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
        # Validate declared content type.
        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid file type. Expected image upload.",
            )

        # Read file content
        content = await file.read()
        if not content:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded file is empty",
            )

        # Validate file size
        if len(content) > self.settings.max_receipt_bytes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File too large. Maximum size is {self.settings.max_receipt_bytes} bytes",
            )

        detected_format, width, height = self._detect_image_metadata(content)
        total_pixels = width * height
        if total_pixels > self.settings.max_receipt_pixels:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Image dimensions are too large. "
                    f"Maximum allowed pixels: {self.settings.max_receipt_pixels}"
                ),
            )

        file_ext, content_type = self._allowed_formats[detected_format]

        # Generate unique storage key: {prefix}/{session_id}/{uuid}.{ext}
        storage_key = f"{self.settings.s3_prefix}/{session_id}/{uuid.uuid4()}{file_ext}"

        # Upload to S3
        try:
            self.s3_client.put_object(
                Bucket=self.settings.s3_bucket_name,
                Key=storage_key,
                Body=content,
                ContentType=content_type,
            )
        except Exception:
            logger.exception("Failed uploading receipt to S3 for session %s", session_id)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to upload receipt to storage",
            )

        return storage_key, content_type

    def get_receipt_bytes(self, storage_key: str) -> bytes:
        """Download receipt image bytes from S3.

        Args:
            storage_key: S3 object key (from ReceiptUpload.storage_key)

        Returns:
            Image bytes

        Raises:
            HTTPException: If download fails
        """
        try:
            response = self.s3_client.get_object(
                Bucket=self.settings.s3_bucket_name,
                Key=storage_key,
            )
            return response["Body"].read()
        except Exception:
            logger.exception("Failed downloading receipt from S3: key=%s", storage_key)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to download receipt from storage",
            )

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
        except Exception:
            logger.exception("Failed generating presigned URL for key=%s", storage_key)
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
        except Exception:
            logger.exception("Failed deleting receipt from S3: key=%s", storage_key)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete receipt from S3",
            )

    def _detect_image_metadata(self, content: bytes) -> tuple[str, int, int]:
        """Verify uploaded image format and decode dimensions safely."""
        try:
            with warnings.catch_warnings():
                # Turn bomb warnings into hard failures for safer uploads.
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(BytesIO(content)) as image:
                    image_format = (image.format or "").upper()
                    width, height = image.size
        except (
            UnidentifiedImageError,
            OSError,
            Image.DecompressionBombError,
            Image.DecompressionBombWarning,
        ):
            image_format = ""
            width, height = 0, 0

        if image_format not in self._allowed_formats:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Unsupported image format. Allowed: JPEG, PNG, WEBP, GIF",
            )
        return image_format, width, height


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
        status=ShoppingSessionStatus.ACTIVE,
    )

    db.add(shopping_session)
    await db.flush()

    # Payer is always a participant by default.
    db.add(
        ShoppingSessionParticipant(
            session_id=shopping_session.id,
            membership_id=paid_by_membership_id,
        )
    )
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

    Any time participants are changed, existing item splits are re-generated
    equally across the full participant set. Item-level sharers can be edited
    afterward via the item sharers endpoint.

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

    if shopping_session.paid_by_membership_id not in participant_membership_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Payer must remain a participant in the session",
        )

    # Validate all participants are members of the group.
    participants = await validate_memberships_in_group(
        db, shopping_session.group_id, participant_membership_ids
    )

    participant_ids = [membership.id for membership in participants]

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

    # Add new participants.
    for membership_id in participant_ids:
        participant = ShoppingSessionParticipant(
            session_id=shopping_session.id,
            membership_id=membership_id,
        )
        db.add(participant)

    # Re-split existing items equally across updated participants.
    # Flush deletions first to satisfy unique(item_id, membership_id).
    for item in shopping_session.items:
        for split in item.splits:
            await db.delete(split)
    await db.flush()

    for item in shopping_session.items:
        share_map = calculate_equal_splits_for_sharers(
            int(item.total_cents),
            sharer_membership_ids=participant_ids,
            payer_membership_id=shopping_session.paid_by_membership_id,
        )

        for membership_id in participant_ids:
            db.add(
                ShoppingItemSplit(
                    item_id=item.id,
                    membership_id=membership_id,
                    share_cents=share_map[membership_id],
                )
            )

    _touch_session_after_financial_mutation(shopping_session)
    await db.flush()
    await db.refresh(shopping_session)

    return shopping_session


async def finalize_shopping_session(
    db: AsyncSession,
    shopping_session: ShoppingSession,
    requester_membership_id: UUID,
) -> ShoppingSession:
    """Mark a shopping session as finalized (payer-only)."""

    if requester_membership_id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can finalize the shopping session",
        )

    if shopping_session.status == ShoppingSessionStatus.SETTLED:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Settled sessions cannot be re-finalized",
        )

    shopping_session.status = ShoppingSessionStatus.FINALIZED
    shopping_session.finalized_at = datetime.now(tz=timezone.utc)
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
        requester_membership_id: Membership ID of requester (must be participant)

    Returns:
        Created receipt upload

    Raises:
        HTTPException: If requester is not participant, session already has a receipt, or upload fails
    """
    participant_ids = {participant.membership_id for participant in shopping_session.participants}
    if not participant_ids:
        # Legacy sessions created before participant auto-seeding.
        participant_ids.add(shopping_session.paid_by_membership_id)

    if requester_membership_id not in participant_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only session participants can upload receipts",
        )

    # Enforce one receipt per shopping session.
    if shopping_session.receipts:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only one receipt is allowed per shopping session. Delete the existing receipt to upload a new one.",
        )

    # Save file to storage
    storage_key, content_type = await receipt_storage.save_receipt(
        file, shopping_session.id
    )

    # Create receipt record
    receipt = ReceiptUpload(
        session_id=shopping_session.id,
        uploaded_by_membership_id=requester_membership_id,
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

    Only the receipt uploader can delete receipts.
    """
    if requester_membership_id != receipt.uploaded_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the receipt uploader can edit or delete this receipt",
        )

    # Delete from S3 first
    receipt_storage.delete_receipt(receipt.storage_key)

    # Delete DB record
    await db.delete(receipt)
    await db.flush()


async def extract_items_from_receipt_upload(
    db: AsyncSession,
    receipt: ReceiptUpload,
) -> list[ReceiptExtractedItem]:
    """Extract items from a receipt image using OCR.
    
    Downloads the receipt from S3, runs OCR, parses items,
    and saves them to the database.
    
    Args:
        db: Database session
        receipt: Receipt upload to extract items from
    
    Returns:
        List of extracted items saved to database
    
    Raises:
        HTTPException: If extraction fails
    """
    import asyncio
    import logging
    
    from fastapi import HTTPException, status as http_status
    
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from app.services.ocr import extract_items_from_receipt as ocr_extract
    
    logger = logging.getLogger(__name__)
    
    import time
    start_time = time.time()
    
    logger.info(f"Starting extraction for receipt {receipt.id}")
    
    try:
        # Wrap entire operation (S3 download + OCR) with timeout
        async def _extract_with_download():
            # Download receipt image from S3 (async-safe)
            logger.info(f"Downloading receipt from S3: {receipt.storage_key}")
            image_bytes = await asyncio.to_thread(
                receipt_storage.get_receipt_bytes,
                receipt.storage_key
            )
            download_time = time.time() - start_time
            logger.info(f"Downloaded {len(image_bytes)} bytes from S3 in {download_time:.2f}s")
            
            # Run OCR and parse items
            logger.info("Starting OCR extraction")
            ocr_start = time.time()
            ocr_items = await ocr_extract(image_bytes)
            ocr_time = time.time() - ocr_start
            logger.info(f"OCR extraction completed in {ocr_time:.2f}s, found {len(ocr_items)} items")
            
            return ocr_items
        
        # Apply 30-second timeout to entire operation
        logger.info("Starting extraction with 30s timeout (S3 download + OCR)")
        ocr_items = await asyncio.wait_for(
            _extract_with_download(),
            timeout=30.0
        )
        
        total_time = time.time() - start_time
        logger.info(f"Extraction completed successfully in {total_time:.2f}s")
        
    except asyncio.TimeoutError:
        elapsed = time.time() - start_time
        logger.error(f"Extraction timed out after {elapsed:.2f}s for receipt {receipt.id}")
        raise HTTPException(
            status_code=http_status.HTTP_504_GATEWAY_TIMEOUT,
            detail="Receipt extraction took too long. Please try with a clearer or smaller image."
        )
    except ValueError as exc:
        # Keep client-facing error explicit for oversized or malformed images.
        raise HTTPException(
            status_code=http_status.HTTP_400_BAD_REQUEST,
            detail=f"Receipt image validation failed: {exc}",
        ) from exc
    
    # Save extracted items to database
    db_items: list[ReceiptExtractedItem] = []
    for ocr_item in ocr_items:
        db_item = ReceiptExtractedItem(
            receipt_upload_id=receipt.id,
            name=ocr_item.name,
            quantity=ocr_item.quantity,
            unit_price_cents=ocr_item.unit_price_cents,
            total_cents=ocr_item.total_cents,
            raw_line=ocr_item.raw_line,
            confidence=ocr_item.confidence,
        )
        db.add(db_item)
        db_items.append(db_item)
    
    await db.flush()
    
    # Refresh to get IDs and timestamps
    for db_item in db_items:
        await db.refresh(db_item)
    
    return db_items


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
        requester_membership_id: Membership ID of requester

    Returns:
        Created shopping item

    Raises:
        HTTPException: If requester is not a session participant
    """
    participant_ids = {participant.membership_id for participant in shopping_session.participants}
    if not participant_ids:
        # Legacy sessions created before participant auto-seeding.
        participant_ids.add(shopping_session.paid_by_membership_id)

    if requester_membership_id not in participant_ids:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only session participants can add items",
        )

    _touch_session_after_financial_mutation(shopping_session)

    # Create item
    item = ShoppingItem(
        session_id=shopping_session.id,
        name=name,
        quantity=quantity,
        total_cents=total_cents,
        unit_price_cents=unit_price_cents,
        created_by_membership_id=requester_membership_id,
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
        requester_membership_id: Membership ID of requester

    Returns:
        List of created splits

    Raises:
        HTTPException: If requester is not authorized or sharers not participants
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

    # Verify requester can manage this item.
    if not await can_manage_item(
        db,
        shopping_session,
        item,
        requester_membership_id=requester_membership_id,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the item creator, payer, or group owner can set sharers",
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
    # Flush deletes before inserts to satisfy unique(item_id, membership_id).
    await db.flush()

    # Calculate equal splits with payer-preferred remainder distribution.
    sharer_ids_in_order = [membership.id for membership in sharers]
    share_map = calculate_equal_splits_for_sharers(
        item.total_cents,
        sharer_membership_ids=sharer_ids_in_order,
        payer_membership_id=shopping_session.paid_by_membership_id,
    )

    # Create new splits
    new_splits = []
    for membership in sharers:
        share_cents = share_map[membership.id]
        split = ShoppingItemSplit(
            item_id=item.id,
            membership_id=membership.id,
            share_cents=share_cents,
        )
        db.add(split)
        new_splits.append(split)

    _touch_session_after_financial_mutation(shopping_session)
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
    db: AsyncSession,
    user_id: UUID,
    group_id: UUID,
    *,
    allow_viewer: bool = True,
) -> Membership:
    """Verify user is a member of the group.

    Args:
        db: Database session
        user_id: User UUID
        group_id: Group UUID

    Returns:
        User's membership in the group

    Raises:
        HTTPException: If user is not a member or lacks required role
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
    if not allow_viewer and membership.role == MembershipRole.VIEWER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Viewers have read-only access in this group",
        )

    return membership
