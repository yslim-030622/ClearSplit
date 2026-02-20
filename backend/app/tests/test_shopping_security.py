"""Security-oriented unit tests for shopping upload safeguards."""

import pytest
from fastapi import HTTPException

from app.services.shopping import _read_upload_with_size_limit


class _ChunkedUploadStub:
    """Minimal async upload stub that yields fixed byte chunks."""

    def __init__(self, chunks: list[bytes]):
        self._chunks = list(chunks)
        self.read_calls = 0

    async def read(self, size: int = -1) -> bytes:
        self.read_calls += 1
        if not self._chunks:
            return b""

        chunk = self._chunks.pop(0)
        if size >= 0 and len(chunk) > size:
            self._chunks.insert(0, chunk[size:])
            return chunk[:size]
        return chunk


@pytest.mark.asyncio
async def test_read_upload_with_size_limit_rejects_empty_payload():
    upload = _ChunkedUploadStub([])

    with pytest.raises(HTTPException) as exc_info:
        await _read_upload_with_size_limit(upload, max_bytes=16)

    assert exc_info.value.status_code == 400
    assert "empty" in exc_info.value.detail.lower()


@pytest.mark.asyncio
async def test_read_upload_with_size_limit_rejects_oversized_payload_early():
    upload = _ChunkedUploadStub(
        [
            b"a" * 8,
            b"b" * 8,
            b"c" * 8,
        ]
    )

    with pytest.raises(HTTPException) as exc_info:
        await _read_upload_with_size_limit(upload, max_bytes=10, chunk_size=8)

    assert exc_info.value.status_code == 400
    assert "file too large" in exc_info.value.detail.lower()
    # Reads only the minimum needed to cross the size threshold.
    assert upload.read_calls == 2


@pytest.mark.asyncio
async def test_read_upload_with_size_limit_returns_content_when_within_limit():
    upload = _ChunkedUploadStub([b"abc", b"def"])

    content = await _read_upload_with_size_limit(upload, max_bytes=10, chunk_size=4)

    assert content == b"abcdef"
