"""Shopping API routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.user import User
from app.schemas.shopping import (
    ParticipantSetRequest,
    ReceiptDownloadURLResponse,
    ReceiptUploadRead,
    SharersSetRequest,
    SharersSetResponse,
    ShoppingItemCreate,
    ShoppingItemRead,
    ShoppingItemSplitRead,
    ShoppingSessionCreate,
    ShoppingSessionRead,
)
from app.services.shopping import (
    create_shopping_item,
    create_shopping_session,
    get_receipt_upload,
    get_shopping_item,
    get_shopping_session,
    list_shopping_sessions,
    receipt_storage,
    set_item_sharers,
    set_session_participants,
    upload_receipt,
    verify_user_is_group_member,
)

router = APIRouter(tags=["shopping"])


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
    await verify_user_is_group_member(db, current_user.id, group_id)

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

    # Convert to read schema
    return ShoppingSessionRead.model_validate(shopping_session)


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
        db, current_user.id, shopping_session.group_id
    )

    # Set participants (service will verify payer authorization)
    shopping_session = await set_session_participants(
        db,
        shopping_session,
        request.participant_membership_ids,
        user_membership.id,
    )

    await db.commit()

    return ShoppingSessionRead.model_validate(shopping_session)


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

    Only the payer can upload receipts.

    Args:
        session_id: Session UUID
        file: Uploaded file
        current_user: Current authenticated user
        db: Database session

    Returns:
        Created receipt upload

    Raises:
        HTTPException: If not authorized or upload fails
    """
    # Get session
    shopping_session = await get_shopping_session(db, session_id)

    # Verify user is a member and get their membership
    user_membership = await verify_user_is_group_member(
        db, current_user.id, shopping_session.group_id
    )

    # Upload receipt (service will verify payer authorization)
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

    Only the payer can create items.

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
        db, current_user.id, shopping_session.group_id
    )

    # Create item (service will verify payer authorization)
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

    Only the payer can set sharers. The system computes equal splits
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
        db, current_user.id, shopping_session.group_id
    )

    # Set sharers (service will verify payer authorization and compute splits)
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

