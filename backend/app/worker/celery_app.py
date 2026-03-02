"""Celery application initialization."""

from celery import Celery

from app.core.config import get_settings

settings = get_settings()

# NOTE: The instance is named `celery_app` (not `celery`) to avoid
# shadowing the celery package and to match the `-A app.worker.celery_app`
# CLI flag used in docker-compose.
celery_app = Celery(
    "clearsplit",
    broker=settings.get_celery_broker_url(),
    backend=settings.get_celery_result_backend(),
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_always_eager=settings.celery_task_always_eager,
    task_eager_propagates=settings.celery_task_eager_propagates,
)

# Auto-discover tasks in worker.tasks
celery_app.autodiscover_tasks(["app.worker"])
