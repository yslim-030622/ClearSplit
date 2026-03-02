"""Pydantic schemas for async job API."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class JobStatusResponse(BaseModel):
    """Full job status (GET /jobs/{id})."""
    id: UUID
    type: str
    status: str
    attempt: int
    max_attempts: int
    created_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    last_error: str | None = None
    result_summary: dict | None = None

    # NOTE: `from_attributes` is intentionally omitted. `type` maps to `AsyncJob.job_type`
    # (the field names differ), so `model_validate(job)` would silently set `type=None`.
    # Always construct explicitly: `JobStatusResponse(type=job.job_type, id=job.id, ...)`
    # as done in jobs.py. Do NOT call `JobStatusResponse.model_validate(job)` directly.


class JobAcceptedResponse(BaseModel):
    """Payload returned with HTTP 202 when a job is enqueued."""
    job_id: UUID
    status: str
    status_url: str
