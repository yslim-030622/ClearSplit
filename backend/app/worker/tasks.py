"""Celery task definitions."""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from app.worker.celery_app import celery_app
from app.worker.db import SyncSessionLocal

logger = logging.getLogger(__name__)


@celery_app.task(
    bind=True,
    max_retries=2,
    default_retry_delay=5,
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_backoff_max=60,
)
def run_receipt_ocr(self, job_id: str, receipt_upload_id: str) -> dict:
    """Execute receipt OCR in the worker process.

    Idempotent: deletes existing extracted items then inserts new ones
    in a single transaction.
    """
    import uuid
    from sqlalchemy import select, delete

    from app.models.async_job import AsyncJob
    from app.models.receipt_extracted_item import ReceiptExtractedItem

    job_uuid = uuid.UUID(job_id)
    receipt_uuid = uuid.UUID(receipt_upload_id)

    with SyncSessionLocal() as db:
        # Mark job as running
        job = db.execute(
            select(AsyncJob).where(AsyncJob.id == job_uuid)
        ).scalar_one_or_none()

        if job is None:
            logger.error("Job %s not found, skipping", job_id)
            return {"error": "job_not_found"}

        if job.status not in ("queued", "running"):
            logger.info("Job %s already in terminal state %s, skipping", job_id, job.status)
            return {"status": job.status}

        job.status = "running"
        job.attempt = (job.attempt or 0) + 1
        job.started_at = datetime.now(tz=timezone.utc)
        db.commit()

    # Perform OCR (sync wrapper)
    try:
        extracted_items_data = _perform_ocr_sync(receipt_uuid)
    except Exception as exc:
        _mark_job_failed(job_uuid, str(exc)[:500], self.request.retries, self.max_retries)
        raise  # Celery auto-retry will catch this

    # Idempotent persistence: delete + insert in one transaction
    with SyncSessionLocal() as db:
        db.execute(
            delete(ReceiptExtractedItem).where(
                ReceiptExtractedItem.receipt_upload_id == receipt_uuid
            )
        )

        for item_data in extracted_items_data:
            item = ReceiptExtractedItem(
                receipt_upload_id=receipt_uuid,
                name=item_data["name"],
                quantity=item_data.get("quantity", 1),
                unit_price_cents=item_data.get("unit_price_cents"),
                total_cents=item_data.get("total_cents", 0),
                raw_line=item_data.get("raw_line"),
                confidence=item_data.get("confidence"),
            )
            db.add(item)

        # Mark job succeeded.
        # Use scalar_one_or_none: in edge cases (e.g. job deleted mid-run) we
        # should log and exit cleanly rather than raise NoResultFound.
        job = db.execute(
            select(AsyncJob).where(AsyncJob.id == job_uuid)
        ).scalar_one_or_none()
        if job is None:
            logger.warning("Job %s disappeared before success update, items saved anyway", job_id)
            db.commit()
            return {"status": "orphaned", "item_count": len(extracted_items_data)}
        job.status = "succeeded"
        job.finished_at = datetime.now(tz=timezone.utc)
        job.result_summary = {"item_count": len(extracted_items_data)}

        db.commit()

    logger.info("Job %s succeeded with %d items", job_id, len(extracted_items_data))
    return {"status": "succeeded", "item_count": len(extracted_items_data)}


def _perform_ocr_sync(receipt_upload_id) -> list[dict]:
    """Download receipt from S3 and run Tesseract OCR (sync).

    Uses the same underlying sync helpers as the async pipeline in
    services/ocr.py but calls them directly — no event loop needed.

    Sync call chain:
      receipt_storage.get_receipt_bytes(storage_key)  → bytes  (boto3, sync)
      _extract_text_from_image_sync(image_bytes)       → str   (Pillow + Tesseract, sync)
      parse_receipt_text(text)                         → list[ExtractedItem]  (pure, sync)
    """
    from sqlalchemy import select

    from app.models.receipt_upload import ReceiptUpload
    from app.services.shopping import receipt_storage
    from app.services.ocr import _extract_text_from_image_sync, parse_receipt_text

    with SyncSessionLocal() as db:
        receipt = db.execute(
            select(ReceiptUpload).where(ReceiptUpload.id == receipt_upload_id)
        ).scalar_one_or_none()
        if receipt is None:
            raise ValueError(f"ReceiptUpload {receipt_upload_id} not found — was it deleted?")
        storage_key = receipt.storage_key

    # Download bytes directly from S3 (sync boto3 call)
    image_bytes = receipt_storage.get_receipt_bytes(storage_key)

    # Run Tesseract OCR synchronously (same function the async path offloads to a thread)
    ocr_text = _extract_text_from_image_sync(image_bytes)

    # Parse into structured items (pure sync)
    extracted_items = parse_receipt_text(ocr_text)

    return [
        {
            "name": item.name,
            "quantity": item.quantity,
            "unit_price_cents": item.unit_price_cents,
            "total_cents": item.total_cents,
            "raw_line": item.raw_line,
            "confidence": item.confidence,
        }
        for item in extracted_items
    ]


def _mark_job_failed(job_id, error_message: str, current_retry: int, max_retries: int) -> None:
    """Mark a job as failed if retries are exhausted."""
    if current_retry >= max_retries:
        with SyncSessionLocal() as db:
            from sqlalchemy import select
            from app.models.async_job import AsyncJob

            job = db.execute(
                select(AsyncJob).where(AsyncJob.id == job_id)
            ).scalar_one_or_none()

            if job:
                job.status = "failed"
                job.finished_at = datetime.now(tz=timezone.utc)
                job.last_error = error_message
                db.commit()
