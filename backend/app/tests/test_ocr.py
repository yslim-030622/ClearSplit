"""Focused OCR service tests."""

import asyncio
import threading
import time

import pytest

from app.services import ocr as ocr_service


@pytest.mark.asyncio
async def test_extract_text_from_image_respects_semaphore_limit(monkeypatch):
    active_calls = 0
    max_active_calls = 0
    call_lock = threading.Lock()

    def fake_extract_text_sync(image_bytes: bytes) -> str:
        nonlocal active_calls, max_active_calls
        with call_lock:
            active_calls += 1
            max_active_calls = max(max_active_calls, active_calls)
        try:
            time.sleep(0.05)
            return image_bytes.decode("utf-8")
        finally:
            with call_lock:
                active_calls -= 1

    monkeypatch.setattr(ocr_service, "_ocr_semaphore", asyncio.Semaphore(1))
    monkeypatch.setattr(ocr_service, "_extract_text_from_image_sync", fake_extract_text_sync)

    results = await asyncio.gather(
        ocr_service.extract_text_from_image(b"alpha"),
        ocr_service.extract_text_from_image(b"beta"),
    )

    assert sorted(results) == ["alpha", "beta"]
    assert max_active_calls == 1
