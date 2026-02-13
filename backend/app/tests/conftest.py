"""Pytest fixtures for backend API/integration tests."""

from collections.abc import AsyncGenerator
from uuid import UUID, uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException, UploadFile, status
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.pool import NullPool

from app.auth.password import hash_password
from app.core.config import get_settings
from app.db.session import get_session
from app.main import app
from app.models.user import User


test_engine = create_async_engine(
    get_settings().get_database_url(),
    echo=False,
    poolclass=NullPool,
)


class TestSession(AsyncSession):
    """Keep test writes inside an outer transaction."""

    async def commit(self) -> None:
        await self.flush()


@pytest_asyncio.fixture(scope="function")
async def session() -> AsyncGenerator[AsyncSession, None]:
    """Create an isolated test transaction per test case."""
    connection = await test_engine.connect()
    transaction = await connection.begin()
    db_session = TestSession(bind=connection, expire_on_commit=False)

    try:
        yield db_session
    finally:
        if transaction.is_active:
            await transaction.rollback()
        await db_session.close()
        await connection.close()


@pytest_asyncio.fixture(scope="function")
async def client(session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """HTTP client with dependency-injected test DB session."""

    async def override_get_session() -> AsyncGenerator[AsyncSession, None]:
        yield session

    app.dependency_overrides[get_session] = override_get_session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def stub_receipt_storage(monkeypatch: pytest.MonkeyPatch) -> dict[str, bytes]:
    """Use in-memory receipt storage to keep tests deterministic and offline."""
    from app.services import shopping as shopping_service

    stored_receipts: dict[str, bytes] = {}

    async def fake_save_receipt(file: UploadFile, session_id: UUID) -> tuple[str, str]:
        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid file type. Expected image/*, got {file.content_type}",
            )

        content = await file.read()
        max_size = shopping_service.receipt_storage.settings.max_receipt_bytes
        if len(content) > max_size:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File too large. Maximum size is {max_size} bytes",
            )

        storage_key = f"test-receipts/{session_id}/{uuid4()}.jpg"
        stored_receipts[storage_key] = content
        return storage_key, file.content_type

    def fake_get_receipt_bytes(storage_key: str) -> bytes:
        if storage_key not in stored_receipts:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Receipt {storage_key} not found in stub storage",
            )
        return stored_receipts[storage_key]

    def fake_create_presigned_get_url(storage_key: str) -> str:
        return f"https://test-storage.local/{storage_key}"

    def fake_delete_receipt(storage_key: str) -> None:
        stored_receipts.pop(storage_key, None)

    monkeypatch.setattr(shopping_service.receipt_storage, "save_receipt", fake_save_receipt)
    monkeypatch.setattr(shopping_service.receipt_storage, "get_receipt_bytes", fake_get_receipt_bytes)
    monkeypatch.setattr(
        shopping_service.receipt_storage,
        "create_presigned_get_url",
        fake_create_presigned_get_url,
    )
    monkeypatch.setattr(shopping_service.receipt_storage, "delete_receipt", fake_delete_receipt)
    return stored_receipts


def create_test_user(
    email: str,
    password: str = "password123",
    username: str | None = None,
    first_name: str = "Test",
    last_name: str = "User",
) -> User:
    """Create a test user model instance with required fields."""
    if username is None:
        username = email.split("@")[0]

    return User(
        username=username,
        email=email,
        password_hash=hash_password(password),
        first_name=first_name,
        last_name=last_name,
    )
