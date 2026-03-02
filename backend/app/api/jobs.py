"""Job status API."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.session import get_session
from app.models.async_job import AsyncJob
from app.models.user import User
from app.schemas.jobs import JobStatusResponse

router = APIRouter(tags=["jobs"])


@router.get("/jobs/{job_id}", response_model=JobStatusResponse)
async def get_job_status(
    job_id: UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> JobStatusResponse:
    """Get the status of an async job."""
    result = await db.execute(
        select(AsyncJob).where(AsyncJob.id == job_id)
    )
    job = result.scalar_one_or_none()

    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found",
        )

    # MVP: creator-only visibility
    if job.created_by_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this job",
        )

    return JobStatusResponse(
        id=job.id,
        type=job.job_type,
        status=job.status,
        attempt=job.attempt,
        max_attempts=job.max_attempts,
        created_at=job.created_at,
        started_at=job.started_at,
        finished_at=job.finished_at,
        last_error=job.last_error,
        result_summary=job.result_summary,
    )
