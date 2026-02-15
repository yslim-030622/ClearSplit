"""Shopping API routes."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.shopping_session import ShoppingSessionStatus
from app.models.user import User
from app.schemas.shopping import (
    ParticipantSetRequest,
    ReceiptDownloadURLResponse,
    ReceiptDeleteResponse,
    ReceiptExtractedItemRead,
    ReceiptUploadRead,
    SharersSetRequest,
    SharersSetResponse,
    ShoppingItemCreate,
    ShoppingItemRead,
    ShoppingItemSplitRead,
    ShoppingSessionCreate,
    ShoppingSessionRead,
    ShoppingSessionUpdate,
)
from app.services.shopping import (
    can_manage_item,
    create_shopping_item,
    create_shopping_session,
    finalize_shopping_session,
    get_receipt_upload,
    get_shopping_item,
    get_shopping_session,
    list_shopping_sessions,
    receipt_storage,
    delete_receipt_upload,
    set_item_sharers,
    set_session_participants,
    upload_receipt,
    verify_user_is_group_member,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["shopping"])


def _reopen_session_after_settlement(shopping_session) -> None:
    """Return a settled/finalized session to active after financial changes."""

    shopping_session.status = ShoppingSessionStatus.ACTIVE
    shopping_session.settled_at = None
    shopping_session.finalized_at = None


# ============================================================================
# Shopping Session endpoints
# ============================================================================


@router.post(
    "/groups/{group_id}/shopping-sessions",
    response_model=ShoppingSessionRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_session(
    group_id: UUID,
    request: ShoppingSessionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingSessionRead:
    """Create a new shopping session.

    Args:
        group_id: Group UUID
        request: Shopping session creation request
        current_user: Current authenticated user
        db: Database session

    Returns:
        Created shopping session

    Raises:
        HTTPException: If validations fail
    """
    # Verify user is a member of the group
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        group_id,
        allow_viewer=False,
    )
    if request.paid_by != user_membership.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only create shopping sessions paid by your own membership",
        )

    # Create shopping session
    shopping_session = await create_shopping_session(
        db,
        group_id=group_id,
        title=request.title,
        paid_by_membership_id=request.paid_by,
        shopping_date=request.shopping_date,
        total_amount=request.total_amount,
    )

    await db.commit()

    # Re-fetch with eager-loaded relationships to avoid async lazy-load during serialization.
    hydrated = await get_shopping_session(db, shopping_session.id)
    return ShoppingSessionRead.model_validate(hydrated)


@router.get(
    "/groups/{group_id}/shopping-sessions",
    response_model=list[ShoppingSessionRead],
)
async def list_sessions(
    group_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ShoppingSessionRead]:
    """List all shopping sessions for a group.

    Args:
        group_id: Group UUID
        current_user: Current authenticated user
        db: Database session

    Returns:
        List of shopping sessions

    Raises:
        HTTPException: If user is not a member
    """
    # Verify user is a member of the group
    await verify_user_is_group_member(db, current_user.id, group_id)

    # List sessions
    sessions = await list_shopping_sessions(db, group_id)

    return [ShoppingSessionRead.model_validate(s) for s in sessions]


@router.get(
    "/shopping-sessions/{session_id}",
    response_model=ShoppingSessionRead,
)
async def get_shopping_session_endpoint(
    session_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingSessionRead:
    """Get a shopping session by ID.

    Args:
        session_id: Session UUID
        current_user: Current authenticated user
        db: Database session

    Returns:
        Shopping session with all related data

    Raises:
        HTTPException: If session not found or user not authorized
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)

    # Verify user is a member of the group
    await verify_user_is_group_member(db, current_user.id, shopping_session.group_id)

    return ShoppingSessionRead.model_validate(shopping_session)


@router.patch(
    "/shopping-sessions/{session_id}",
    response_model=ShoppingSessionRead,
)
async def update_shopping_session(
    session_id: UUID,
    request: ShoppingSessionUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingSessionRead:
    """Update a shopping session (title, date, total_amount).
    
    Only the payer can update the session.
    
    Args:
        session_id: Session UUID
        request: Updated session data
        current_user: Current authenticated user
        db: Database session
    
    Returns:
        Updated shopping session
    
    Raises:
        HTTPException: If session not found, user not payer, or validation fails
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)
    
    # Verify user is a member of the group
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    
    # Verify requester is the payer
    if user_membership.id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can update the shopping session",
        )
    
    if request.title is not None:
        shopping_session.title = request.title
    if request.shopping_date is not None:
        shopping_session.shopping_date = request.shopping_date
    if request.total_amount is not None:
        shopping_session.total_amount = request.total_amount
    if request.status is not None:
        if request.status == ShoppingSessionStatus.SETTLED:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Session status 'settled' is managed automatically by payments",
            )
        if request.status == ShoppingSessionStatus.FINALIZED:
            shopping_session.status = ShoppingSessionStatus.FINALIZED
            if shopping_session.finalized_at is None:
                from datetime import datetime, timezone
                shopping_session.finalized_at = datetime.now(tz=timezone.utc)
        if request.status == ShoppingSessionStatus.ACTIVE:
            _reopen_session_after_settlement(shopping_session)

    await db.commit()

    # Re-fetch with eager-loaded relationships to avoid async lazy-load during serialization.
    hydrated = await get_shopping_session(db, shopping_session.id)
    return ShoppingSessionRead.model_validate(hydrated)


@router.post(
    "/shopping-sessions/{session_id}/finalize",
    response_model=ShoppingSessionRead,
)
async def finalize_session(
    session_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingSessionRead:
    """Finalize a shopping session so only settlement progress remains."""

    shopping_session = await get_shopping_session(db, session_id)
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    updated = await finalize_shopping_session(
        db,
        shopping_session,
        requester_membership_id=user_membership.id,
    )
    await db.commit()

    # Re-fetch with eager-loaded relationships to avoid async lazy-load during serialization.
    hydrated = await get_shopping_session(db, updated.id)
    return ShoppingSessionRead.model_validate(hydrated)


@router.delete(
    "/shopping-sessions/{session_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_shopping_session(
    session_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    """Delete a shopping session and all related data.
    
    Only the payer can delete the session.
    Cascades to: participants, items, item splits, receipts (and S3 objects).
    
    Args:
        session_id: Session UUID
        current_user: Current authenticated user
        db: Database session
    
    Raises:
        HTTPException: If session not found or user not payer
    """
    from app.models.shopping_session_participant import ShoppingSessionParticipant
    from app.models.shopping_item_split import ShoppingItemSplit
    from sqlalchemy import select
    
    # Get session
    shopping_session = await get_shopping_session(db, session_id)
    
    # Verify user is a member of the group
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    
    # Verify requester is the payer
    if user_membership.id != shopping_session.paid_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the payer can delete the shopping session",
        )
    
    # Delete receipts from S3 and DB
    for receipt in shopping_session.receipts:
        try:
            await receipt_storage.delete_receipt(receipt.storage_key)
        except Exception as e:
            # Log but don't fail - orphaned S3 objects can be cleaned up later
            logger.warning("Failed deleting receipt key=%s from storage: %s", receipt.storage_key, e)
        await db.delete(receipt)
    
    # Delete item splits
    for item in shopping_session.items:
        result = await db.execute(
            select(ShoppingItemSplit).where(ShoppingItemSplit.item_id == item.id)
        )
        splits = result.scalars().all()
        for split in splits:
            await db.delete(split)
    
    # Delete items
    for item in shopping_session.items:
        await db.delete(item)
    
    # Delete participants
    result = await db.execute(
        select(ShoppingSessionParticipant).where(
            ShoppingSessionParticipant.session_id == session_id
        )
    )
    participants = result.scalars().all()
    for participant in participants:
        await db.delete(participant)
    
    # Delete session
    await db.delete(shopping_session)
    await db.commit()


@router.put(
    "/shopping-sessions/{session_id}/participants",
    response_model=ShoppingSessionRead,
)
async def set_participants(
    session_id: UUID,
    request: ParticipantSetRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingSessionRead:
    """Set/replace participants for a shopping session.

    Only the payer can set participants.

    Args:
        session_id: Session UUID
        request: Participant set request
        current_user: Current authenticated user
        db: Database session

    Returns:
        Updated shopping session

    Raises:
        HTTPException: If not authorized or validation fails
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)

    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )

    # Set participants (service will verify payer authorization)
    shopping_session = await set_session_participants(
        db,
        shopping_session,
        request.participant_membership_ids,
        user_membership.id,
    )

    await db.commit()

    # Re-fetch with eager-loaded relationships to avoid async lazy-load during serialization.
    hydrated = await get_shopping_session(db, shopping_session.id)
    return ShoppingSessionRead.model_validate(hydrated)


# ============================================================================
# Receipt endpoints
# ============================================================================


@router.post(
    "/shopping-sessions/{session_id}/receipt",
    response_model=ReceiptUploadRead,
    status_code=status.HTTP_201_CREATED,
)
async def upload_session_receipt(
    session_id: UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ReceiptUploadRead:
    """Upload a receipt for a shopping session.

    Only session participants can upload receipts.
    Exactly one receipt is allowed per shopping session.

    Args:
        session_id: Session UUID
        file: Uploaded file
        current_user: Current authenticated user
        db: Database session

    Returns:
        Created receipt upload

    Raises:
        HTTPException: If not authorized, session already has a receipt, or upload fails
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)

    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )

    # Upload receipt (service verifies participant authorization + one-receipt rule)
    receipt = await upload_receipt(
        db,
        shopping_session,
        file,
        user_membership.id,
    )

    await db.commit()

    return ReceiptUploadRead.model_validate(receipt)


@router.get(
    "/receipts/{receipt_upload_id}/download-url",
    response_model=ReceiptDownloadURLResponse,
)
async def get_receipt_download_url(
    receipt_upload_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ReceiptDownloadURLResponse:
    """Get a presigned download URL for a receipt.

    User must be a member of the receipt's shopping session group.

    Args:
        receipt_upload_id: Receipt upload UUID
        current_user: Current authenticated user
        db: Database session

    Returns:
        Presigned download URL response

    Raises:
        HTTPException: If receipt not found or user not authorized
    """
    # Load receipt upload
    receipt = await get_receipt_upload(db, receipt_upload_id)

    # Load shopping session to get group_id
    shopping_session = await get_shopping_session(db, receipt.session_id)

    # Verify user is a member of the group
    await verify_user_is_group_member(db, current_user.id, shopping_session.group_id)

    # Generate presigned URL
    presigned_url = receipt_storage.create_presigned_get_url(receipt.storage_key)

    # Get expiration from settings
    from app.core.config import get_settings
    settings = get_settings()

    return ReceiptDownloadURLResponse(
        receipt_upload_id=receipt.id,
        expires_in_seconds=settings.s3_presigned_get_expire_seconds,
        url=presigned_url,
    )


@router.delete(
    "/receipts/{receipt_upload_id}",
    response_model=ReceiptDeleteResponse,
)
async def delete_receipt(
    receipt_upload_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ReceiptDeleteResponse:
    """Delete a receipt upload (uploader only)."""
    receipt = await get_receipt_upload(db, receipt_upload_id)
    shopping_session = await get_shopping_session(db, receipt.session_id)

    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )

    await delete_receipt_upload(db, receipt, shopping_session, user_membership.id)
    await db.commit()

    return ReceiptDeleteResponse(
        receipt_upload_id=receipt.id,
        deleted=True,
    )


# ============================================================================
# Shopping Item endpoints
# ============================================================================


@router.post(
    "/shopping-sessions/{session_id}/items",
    response_model=ShoppingItemRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_item(
    session_id: UUID,
    request: ShoppingItemCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingItemRead:
    """Create a shopping item.

    Any session participant can create items.

    Args:
        session_id: Session UUID
        request: Shopping item creation request
        current_user: Current authenticated user
        db: Database session

    Returns:
        Created shopping item

    Raises:
        HTTPException: If not authorized or validation fails
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)

    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )

    # Create item (service will verify participant authorization)
    item = await create_shopping_item(
        db,
        shopping_session,
        name=request.name,
        quantity=request.quantity,
        total_cents=request.total_cents,
        unit_price_cents=request.unit_price_cents,
        requester_membership_id=user_membership.id,
    )

    await db.commit()

    return ShoppingItemRead.model_validate(item)


@router.patch(
    "/items/{item_id}",
    response_model=ShoppingItemRead,
)
async def update_item(
    item_id: UUID,
    request: ShoppingItemCreate,  # Reuse same schema for update
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> ShoppingItemRead:
    """Update a shopping item (name, quantity, price).
    
    Only the item creator, payer, or group owner can update items.
    If total_cents changes, existing splits are invalidated and must be reset.
    
    Args:
        item_id: Item UUID
        request: Updated item data
        current_user: Current authenticated user
        db: Database session
    
    Returns:
        Updated shopping item
    
    Raises:
        HTTPException: If not authorized or validation fails
    """
    from app.models.shopping_item_split import ShoppingItemSplit
    from sqlalchemy import select
    
    # Get item
    item = await get_shopping_item(db, item_id)
    
    # Get session to verify authorization
    shopping_session = await get_shopping_session(db, item.session_id)
    
    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    
    # Verify requester can manage this item
    if not await can_manage_item(
        db,
        shopping_session,
        item,
        requester_membership_id=user_membership.id,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the item creator, payer, or group owner can update items",
        )

    if shopping_session.status == ShoppingSessionStatus.SETTLED:
        _reopen_session_after_settlement(shopping_session)
    
    # If total_cents changed, delete existing splits (they're now invalid)
    if item.total_cents != request.total_cents:
        result = await db.execute(
            select(ShoppingItemSplit).where(ShoppingItemSplit.item_id == item_id)
        )
        splits = result.scalars().all()
        for split in splits:
            await db.delete(split)
    
    # Update fields
    item.name = request.name
    item.quantity = request.quantity
    item.total_cents = request.total_cents
    item.unit_price_cents = request.unit_price_cents
    
    await db.commit()
    await db.refresh(item)
    
    return ShoppingItemRead.model_validate(item)


@router.delete(
    "/items/{item_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_item(
    item_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    """Delete a shopping item and its splits.
    
    Only the item creator, payer, or group owner can delete items.
    
    Args:
        item_id: Item UUID
        current_user: Current authenticated user
        db: Database session
    
    Raises:
        HTTPException: If not authorized
    """
    from app.models.shopping_item_split import ShoppingItemSplit
    from sqlalchemy import select
    
    # Get item
    item = await get_shopping_item(db, item_id)
    
    # Get session to verify authorization
    shopping_session = await get_shopping_session(db, item.session_id)
    
    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    
    # Verify requester can manage this item
    if not await can_manage_item(
        db,
        shopping_session,
        item,
        requester_membership_id=user_membership.id,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the item creator, payer, or group owner can delete items",
        )

    if shopping_session.status == ShoppingSessionStatus.SETTLED:
        _reopen_session_after_settlement(shopping_session)
    
    # Delete splits
    result = await db.execute(
        select(ShoppingItemSplit).where(ShoppingItemSplit.item_id == item_id)
    )
    splits = result.scalars().all()
    for split in splits:
        await db.delete(split)
    
    # Delete item
    await db.delete(item)
    await db.commit()


@router.put(
    "/items/{item_id}/sharers",
    response_model=SharersSetResponse,
)
async def set_sharers(
    item_id: UUID,
    request: SharersSetRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> SharersSetResponse:
    """Set/replace sharers for a shopping item.

    Only the item creator, payer, or group owner can set sharers. The system computes equal splits
    automatically with deterministic remainder distribution.

    Args:
        item_id: Item UUID
        request: Sharers set request
        current_user: Current authenticated user
        db: Database session

    Returns:
        Item with computed splits

    Raises:
        HTTPException: If not authorized or validation fails
    """
    # Get item
    item = await get_shopping_item(db, item_id)

    # Get session to verify authorization
    shopping_session = await get_shopping_session(db, item.session_id)

    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )

    # Set sharers (service verifies item-management permissions and computes splits)
    splits = await set_item_sharers(
        db,
        item,
        request.membership_ids,
        user_membership.id,
    )

    await db.commit()

    # Build response
    return SharersSetResponse(
        item_id=item.id,
        total_cents=item.total_cents,
        splits=[ShoppingItemSplitRead.model_validate(s) for s in splits],
    )


# ============================================================================
# Receipt OCR endpoints
# ============================================================================


@router.post(
    "/receipts/{receipt_upload_id}/extract-items",
    response_model=list[ReceiptExtractedItemRead],
    status_code=status.HTTP_200_OK,
)
async def extract_items_from_receipt_endpoint(
    receipt_upload_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ReceiptExtractedItemRead]:
    """Extract items from a receipt image using OCR.
    
    Only the receipt uploader can trigger extraction. This endpoint is idempotent:
    if items have already been extracted, it returns the existing items
    instead of re-running OCR.
    
    Args:
        receipt_upload_id: Receipt upload UUID
        current_user: Current authenticated user
        db: Database session
    
    Returns:
        List of extracted items
    
    Raises:
        HTTPException: If not authorized or extraction fails
    """
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from app.services.shopping import extract_items_from_receipt_upload
    from sqlalchemy import select
    
    # Get receipt
    receipt = await get_receipt_upload(db, receipt_upload_id)
    
    # Get session to verify authorization
    shopping_session = await get_shopping_session(db, receipt.session_id)
    
    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db,
        current_user.id,
        shopping_session.group_id,
        allow_viewer=False,
    )
    
    # Verify requester is the receipt uploader.
    if user_membership.id != receipt.uploaded_by_membership_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the receipt uploader can extract items",
        )
    
    # Check if items already extracted (idempotency)
    logger.info("[EXTRACT-ITEMS] Checking for existing extracted items")
    result = await db.execute(
        select(ReceiptExtractedItem)
        .where(ReceiptExtractedItem.receipt_upload_id == receipt_upload_id)
        .order_by(ReceiptExtractedItem.created_at)
    )
    existing_items = list(result.scalars().all())
    
    if existing_items:
        # Return existing items
        logger.info(f"[EXTRACT-ITEMS] Returning {len(existing_items)} existing items (idempotent)")
        return [ReceiptExtractedItemRead.model_validate(item) for item in existing_items]
    
    # Extract items (OCR + parsing + DB save)
    logger.info("[EXTRACT-ITEMS] Starting new extraction")
    extracted_items = await extract_items_from_receipt_upload(db, receipt)
    
    logger.info(f"[EXTRACT-ITEMS] Committing {len(extracted_items)} items to database")
    await db.commit()
    
    logger.info(f"[EXTRACT-ITEMS] Successfully completed extraction for receipt {receipt_upload_id}")
    return [ReceiptExtractedItemRead.model_validate(item) for item in extracted_items]


@router.get(
    "/receipts/{receipt_upload_id}/extracted-items",
    response_model=list[ReceiptExtractedItemRead],
)
async def get_extracted_items_endpoint(
    receipt_upload_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ReceiptExtractedItemRead]:
    """Get previously extracted items for a receipt.
    
    Any group member can view extracted items.
    
    Args:
        receipt_upload_id: Receipt upload UUID
        current_user: Current authenticated user
        db: Database session
    
    Returns:
        List of extracted items
    
    Raises:
        HTTPException: If not authorized
    """
    from app.models.receipt_extracted_item import ReceiptExtractedItem
    from sqlalchemy import select
    
    # Get receipt
    receipt = await get_receipt_upload(db, receipt_upload_id)
    
    # Get session to verify authorization
    shopping_session = await get_shopping_session(db, receipt.session_id)
    
    # Verify user is a member (any member can view)
    await verify_user_is_group_member(db, current_user.id, shopping_session.group_id)
    
    # Get extracted items
    result = await db.execute(
        select(ReceiptExtractedItem)
        .where(ReceiptExtractedItem.receipt_upload_id == receipt_upload_id)
        .order_by(ReceiptExtractedItem.created_at)
    )
    extracted_items = list(result.scalars().all())
    
    return [ReceiptExtractedItemRead.model_validate(item) for item in extracted_items]
