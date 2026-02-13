"""OCR service for receipt text extraction and parsing."""

import asyncio
import io
import logging
import re
import warnings
from typing import NamedTuple

from app.core.config import get_settings

try:
    from PIL import Image
except ModuleNotFoundError:  # pragma: no cover - depends on optional OCR runtime install
    Image = None  # type: ignore[assignment]

try:
    import pytesseract
except ModuleNotFoundError:  # pragma: no cover - depends on optional OCR runtime install
    pytesseract = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)
settings = get_settings()
_MAX_RECEIPT_PIXELS = max(1, settings.max_receipt_pixels)
_MAX_OCR_CONCURRENCY = max(1, settings.max_ocr_concurrency)
_ocr_semaphore = asyncio.Semaphore(_MAX_OCR_CONCURRENCY)


class ExtractedItem(NamedTuple):
    """Parsed item from receipt OCR."""

    name: str
    quantity: int
    unit_price_cents: int | None
    total_cents: int
    raw_line: str
    confidence: float


# Keywords to exclude (not product lines)
EXCLUDE_KEYWORDS = {
    "TOTAL", "SUBTOTAL", "TAX", "CHANGE", "CASH", "VISA", "MASTER", "MASTERCARD",
    "BALANCE", "TIP", "DISCOUNT", "SALE", "SAVINGS", "DEBIT", "CREDIT", "CARD",
    "PAYMENT", "TENDER", "AMOUNT", "DUE", "PAID", "RECEIPT", "THANK", "WELCOME",
    "STORE", "DATE", "TIME", "CASHIER", "TRANSACTION", "NUMBER", "#", "QTY",
}


def _extract_text_from_image_sync(image_bytes: bytes) -> str:
    """Synchronous OCR extraction (runs in thread pool).
    
    Args:
        image_bytes: Image file bytes
    
    Returns:
        Extracted text string
    """
    logger.info("Starting Tesseract OCR extraction")
    
    # Load image and convert to grayscale for better OCR
    if Image is None:
        raise RuntimeError("Pillow is not installed")
    Image.MAX_IMAGE_PIXELS = _MAX_RECEIPT_PIXELS
    try:
        with warnings.catch_warnings():
            # Make decompression bombs fail fast instead of warning.
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(image_bytes)) as source_image:
                image = source_image.convert("L")
    except (Image.DecompressionBombError, Image.DecompressionBombWarning, OSError) as exc:
        raise ValueError("Image is too large or malformed") from exc

    if image.width * image.height > _MAX_RECEIPT_PIXELS:
        raise ValueError("Image dimensions exceed OCR safety limit")
    
    # Downscale if image is very large (improves performance)
    max_dimension = 2000
    if image.width > max_dimension or image.height > max_dimension:
        logger.info(f"Downscaling image from {image.width}x{image.height}")
        image.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)
        logger.info(f"Image downscaled to {image.width}x{image.height}")
    
    # Run Tesseract OCR
    # --oem 1: Use LSTM neural net mode
    # --psm 6: Assume a single uniform block of text
    if pytesseract is None:
        raise RuntimeError("pytesseract is not installed")

    text = pytesseract.image_to_string(
        image,
        lang="eng",
        config="--oem 1 --psm 6"
    )
    
    logger.info(f"Tesseract OCR completed, extracted {len(text)} characters")
    return text


async def extract_text_from_image(image_bytes: bytes) -> str:
    """Extract text from receipt image using Tesseract OCR (async-safe).
    
    Args:
        image_bytes: Image file bytes
    
    Returns:
        Extracted text string
    """
    # Bound OCR concurrency so expensive requests cannot starve the app.
    async with _ocr_semaphore:
        text = await asyncio.to_thread(_extract_text_from_image_sync, image_bytes)
        return text


def parse_receipt_text(text: str) -> list[ExtractedItem]:
    """Parse OCR text into structured items.
    
    Args:
        text: Raw OCR text from receipt
    
    Returns:
        List of extracted items with prices
    """
    items: list[ExtractedItem] = []
    lines = text.split("\n")
    
    # Price regex: matches formats like 1.99, 12.50, 0.99
    price_pattern = re.compile(r'(\d+[.,]\d{2})')
    
    # Quantity patterns: "2 x", "3x", "2 @", "2@"
    qty_pattern = re.compile(r'^(\d+)\s*[x@]\s*', re.IGNORECASE)
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines
        if not line:
            continue
        
        # Skip lines with exclude keywords
        line_upper = line.upper()
        if any(keyword in line_upper for keyword in EXCLUDE_KEYWORDS):
            continue
        
        # Find all prices in the line
        prices = price_pattern.findall(line)
        if not prices:
            continue
        
        # Use the last price on the line (typically the total)
        price_str = prices[-1].replace(',', '.')
        try:
            price_float = float(price_str)
            total_cents = int(price_float * 100)
        except ValueError:
            continue
        
        # Skip if price is 0 or negative
        if total_cents <= 0:
            continue
        
        # Extract item name (everything before the last price)
        last_price_pos = line.rfind(prices[-1])
        name = line[:last_price_pos].strip()
        
        # Skip if name is too short or empty
        if len(name) < 2:
            continue
        
        # Try to extract quantity
        quantity = 1
        unit_price_cents = None
        
        qty_match = qty_pattern.match(name)
        if qty_match:
            try:
                quantity = int(qty_match.group(1))
                # Remove quantity prefix from name
                name = qty_pattern.sub('', name).strip()
                # Calculate unit price
                if quantity > 0:
                    unit_price_cents = total_cents // quantity
            except ValueError:
                pass
        
        # Calculate confidence score (simple heuristic)
        confidence = calculate_confidence(name, total_cents, line)
        
        # Skip low-confidence items
        if confidence < 0.3:
            continue
        
        items.append(ExtractedItem(
            name=name,
            quantity=quantity,
            unit_price_cents=unit_price_cents,
            total_cents=total_cents,
            raw_line=line,
            confidence=confidence,
        ))
    
    return items


def calculate_confidence(name: str, total_cents: int, raw_line: str) -> float:
    """Calculate confidence score for an extracted item.
    
    Simple heuristic based on:
    - Name length (longer is better)
    - Price reasonableness (not too high/low)
    - Presence of letters in name
    
    Args:
        name: Item name
        total_cents: Total price in cents
        raw_line: Original OCR line
    
    Returns:
        Confidence score between 0.0 and 1.0
    """
    score = 0.5  # Base score
    
    # Name length bonus (up to +0.2)
    if len(name) >= 10:
        score += 0.2
    elif len(name) >= 5:
        score += 0.1
    
    # Has letters bonus (+0.2)
    if any(c.isalpha() for c in name):
        score += 0.2
    
    # Price reasonableness (between $0.10 and $100.00)
    if 10 <= total_cents <= 10000:
        score += 0.1
    
    # Penalize very short names
    if len(name) < 3:
        score -= 0.3
    
    # Penalize names that are mostly numbers
    if sum(c.isdigit() for c in name) > len(name) * 0.5:
        score -= 0.2
    
    return max(0.0, min(1.0, score))


async def extract_items_from_receipt(image_bytes: bytes) -> list[ExtractedItem]:
    """Complete pipeline: OCR + parsing (async-safe).
    
    Args:
        image_bytes: Receipt image bytes
    
    Returns:
        List of extracted items
    """
    logger.info("Starting OCR extraction pipeline")
    text = await extract_text_from_image(image_bytes)
    logger.info("Parsing extracted text into items")
    items = parse_receipt_text(text)
    logger.info(f"Extracted {len(items)} items from receipt")
    return items
