"""Prometheus metrics endpoint."""

from fastapi import APIRouter
from fastapi.responses import PlainTextResponse
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

from app.core.config import get_settings

router = APIRouter(tags=["metrics"])

# Define metrics
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint"],
)
CACHE_HIT = Counter("cache_hits_total", "Cache hits", ["cache_name"])
CACHE_MISS = Counter("cache_misses_total", "Cache misses", ["cache_name"])
JOB_COUNT = Counter("jobs_total", "Background jobs", ["type", "outcome"])
JOB_DURATION = Histogram("job_duration_seconds", "Background job duration", ["type"])


@router.get("/metrics")
async def metrics() -> PlainTextResponse:
    settings = get_settings()
    if not settings.prometheus_enabled:
        return PlainTextResponse("Metrics disabled", status_code=404)
    return PlainTextResponse(
        generate_latest().decode("utf-8"),
        media_type=CONTENT_TYPE_LATEST,
    )
