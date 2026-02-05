# Receipt OCR Implementation - Product & Technical Decisions

This document addresses all product and technical decisions needed to implement receipt OCR parsing in ClearSplit. Each decision includes recommendations, rationale, and implementation implications.

**Status**: ⚠️ **DECISIONS PENDING** - Review and approve each section before implementation.

---

## 1. Product Scope

### 1.1 MVP Success Criteria

**Question**: What's the MVP success criteria? Is it "auto-generate a decent draft list" + user fixes it, or do you expect near-perfect extraction?

**Recommendation**: ✅ **"Decent draft + user fixes"**

**Rationale**:

- Perfect OCR is impossible (receipt formats vary wildly)
- User review is essential for accuracy (money is involved)
- Reduces complexity and cost (no need for perfect ML models)
- Better UX: users feel in control

**Implementation**:

- Parser should extract 70-80% of items correctly
- User can edit/delete/add items before confirming
- Clear visual indicators for draft vs confirmed state

**Alternative Considered**: Near-perfect extraction

- ❌ Too expensive (requires advanced ML)
- ❌ Too slow (complex models)
- ❌ Still needs user verification (trust issues)

---

### 1.2 Receipts Per Session

**Question**: How many receipts per shopping session? One receipt only, or multiple images/pages per session?

**Recommendation**: ✅ **Multiple receipts per session**

**Rationale**:

- Real-world: people shop at multiple stores in one trip
- Current model supports multiple `ReceiptUpload` records per session
- Simpler UX: "Add another receipt" button

**Implementation**:

- Each receipt gets its own OCR extraction
- Items from all receipts aggregate into one session
- Receipt metadata links to source receipt

**Alternative Considered**: One receipt only

- ❌ Too limiting for real use cases
- ❌ Would require "merge sessions" feature later

---

### 1.3 Currency Support

**Question**: Do you want to support only USD initially, or multiple currencies/number formats? (e.g., 1.99 vs 1,99, currency symbols, etc.)

**Recommendation**: ✅ **USD only for MVP, but parser should be locale-aware**

**Rationale**:

- Faster to ship MVP
- Most users are US-based initially
- Parser can be extended later without breaking changes

**Implementation**:

- Parser hardcodes USD format: `$X.XX` or `X.XX`
- Store currency in `ShoppingSession.currency` (already exists, defaults to "USD")
- Parser ignores currency symbols but validates format
- Future: add `locale` parameter to parser

**Alternative Considered**: Multi-currency from start

- ❌ Adds complexity (number format detection, currency conversion)
- ❌ Harder to test all formats
- ✅ Can add later without breaking changes

---

### 1.4 Store/Receipt Types

**Question**: Which stores/receipt types are you targeting first? (Costco/Target/Walmart/restaurant receipts) This impacts parsing rules.

**Recommendation**: ✅ **Start with major grocery chains: Target, Walmart, Costco, Kroger, Safeway**

**Rationale**:

- Most common for roommates
- Similar format (item name + price per line)
- Easier to parse than restaurant receipts (which have descriptions, modifiers)

**Implementation**:

- Parser rules for common grocery formats:
  - `ITEM NAME                    $X.XX`
  - `ITEM NAME @ $X.XX EA        $Y.YY`
- Store detection (optional): try to identify store from header
- Fallback: generic parser for unknown formats

**Future Expansion**:

- Restaurant receipts (more complex: items + modifiers)
- Pharmacy receipts (different format)
- Gas station receipts (fewer items)

---

## 2. iOS OCR Output Contract

### 2.1 Data Format from iOS

**Question**: What will the iOS app send to the backend? raw text as one big string? an array of lines? per-line bounding boxes/confidence (Vision provides some of this)?

**Recommendation**: ✅ **Array of lines with metadata**

**Structure**:

```json
{
  "receipt_id": "uuid",
  "lines": [
    {
      "text": "MILK 2% GAL",
      "confidence": 0.95,
      "bounding_box": {"x": 10, "y": 50, "width": 200, "height": 20},
      "line_number": 1
    }
  ],
  "metadata": {
    "ocr_provider": "apple_vision",
    "image_width": 1024,
    "image_height": 2048,
    "detected_store": "TARGET" // optional
  }
}
```

**Rationale**:

- Vision framework provides line-level data
- Confidence scores help parser prioritize
- Bounding boxes enable future features (highlighting, re-OCR regions)
- Line numbers help with debugging

**Alternative Considered**: Raw text string

- ❌ Loses valuable metadata
- ❌ Harder to debug parsing issues
- ❌ Can't improve parser based on confidence

---

### 2.2 Store Original OCR Output

**Question**: Do you want the backend to store the original OCR output exactly as received? (Recommended for debugging / replay.)

**Recommendation**: ✅ **Yes, store raw OCR output**

**Rationale**:

- Critical for debugging parsing failures
- Allows re-running parser with improved rules
- User support: "Why did this parse wrong?"
- Analytics: improve parser accuracy over time

**Implementation**:

- New table: `receipt_ocr_extractions`
  - `id`, `receipt_upload_id`, `raw_ocr_data` (JSONB)
  - `extracted_at`, `parser_version`
- Store full iOS payload as JSONB
- Link to `receipt_uploads` table

**Alternative Considered**: Don't store

- ❌ Can't debug issues
- ❌ Can't improve parser
- ❌ Poor user support experience

---

### 2.3 Max Receipt Size

**Question**: What's the expected max receipt size? Number of lines / characters. (Impacts DB fields, request size limits.)

**Recommendation**: ✅ **100 lines max, ~10KB per receipt**

**Rationale**:

- Typical grocery receipt: 20-50 items
- 100 lines covers 99th percentile
- 10KB is reasonable for JSON payload
- FastAPI default body limit is 1MB (plenty of headroom)

**Implementation**:

- Validate on backend: reject if > 100 lines
- DB: `Text` field for raw OCR (unlimited, but validate)
- Request validation: max 50KB per extraction request
- Error message: "Receipt too large. Please split into multiple sessions."

**Real-world examples**:

- Small receipt: 10-20 lines
- Medium receipt: 30-50 lines
- Large receipt (Costco): 60-80 lines
- Extreme: 100+ lines (rare, but possible)

---

## 3. Receipt File Storage (S3) Decisions

### 3.1 Upload Flow

**Question**: Will the iOS app upload directly to S3 via presigned URL? Or will it upload to your backend and the backend uploads to S3?

**Recommendation**: ✅ **Backend uploads to S3 (for MVP), presigned URLs later**

**Rationale**:

- Simpler for MVP: one upload endpoint
- Backend can validate file before S3
- Easier to add processing (OCR trigger, virus scan)
- Can switch to presigned URLs later without breaking iOS

**Implementation**:

- Current: iOS → Backend → Local filesystem
- MVP: iOS → Backend → S3 (backend handles S3 client)
- Future: iOS → S3 (presigned URL) + Backend (metadata)

**Alternative Considered**: Presigned URLs from start

- ❌ More complex (S3 setup, URL generation)
- ❌ Harder to validate files
- ✅ Better for scale (less backend bandwidth)
- ✅ Can add later

---

### 3.2 Receipt Privacy

**Question**: Should receipts be private only? Download only via presigned GET, no public URLs?

**Recommendation**: ✅ **Private only, presigned GET URLs**

**Rationale**:

- Receipts contain sensitive data (purchases, location, time)
- Privacy requirement for financial data
- Presigned URLs: time-limited, user-specific access
- No public URLs = better security

**Implementation**:

- S3 bucket: private, no public access
- Backend generates presigned GET URLs (15 min expiry)
- iOS requests URL from backend when viewing receipt
- Backend verifies user is session member before generating URL

**Alternative Considered**: Public URLs

- ❌ Security risk
- ❌ Privacy concerns
- ❌ No access control

---

### 3.3 Delete/Replace Behavior

**Question**: Do you need delete/replace behavior? If user re-uploads, do we keep old files (audit) or delete them?

**Recommendation**: ✅ **Keep old files (audit trail), mark as superseded**

**Rationale**:

- Audit trail: "What was the original receipt?"
- User support: "Show me the receipt from last week"
- Legal/compliance: may need historical receipts
- Storage is cheap

**Implementation**:

- `ReceiptUpload` table: add `superseded_by_id` (nullable FK)
- On re-upload: create new record, link old one
- Keep all files in S3 (don't delete)
- UI: show latest receipt, allow viewing history

**Alternative Considered**: Delete old files

- ❌ Loses audit trail
- ❌ Can't recover if user makes mistake
- ✅ Saves storage (minimal savings)

---

## 4. Parsing Behavior and Rules

### 4.1 Required Draft Item Fields

**Question**: What fields are required for a draft item in MVP? name + total only (recommended) or quantity/unit price too? (optional)

**Recommendation**: ✅ **name + total_cents (required), quantity + unit_price_cents (optional)**

**Rationale**:

- Name + total are always available on receipts
- Quantity/unit price are often missing or ambiguous
- User can fill in quantity/unit price during review
- Matches current `ShoppingItem` model

**Implementation**:

- Parser extracts: `name` (required), `total_cents` (required)
- Parser attempts: `quantity`, `unit_price_cents` (if clear)
- User can edit all fields before confirming
- Validation: `total_cents = quantity * unit_price_cents` (if both provided)

**Draft Item Schema**:

```python
{
  "name": "MILK 2% GAL",  # required
  "total_cents": 499,      # required
  "quantity": 1,           # optional
  "unit_price_cents": 499  # optional
}
```

---

### 4.2 Non-Item Lines

**Question**: How should we treat non-item lines? Ignore: TOTAL/SUBTOTAL/TAX/PAYMENT/CHANGE? What about DISCOUNT/COUPON/STORE CREDIT? Ignore in MVP or represent as negative items?

**Recommendation**: ✅ **Ignore totals/taxes/payment in MVP, represent discounts as negative items**

**Rationale**:

- Totals/taxes are metadata, not items to split
- Discounts/coupons affect item prices (should be tracked)
- Store credit is a payment method (ignore)
- Keeps parser simple for MVP

**Implementation**:

- **Ignore**: TOTAL, SUBTOTAL, TAX, SALES TAX, PAYMENT, CHANGE, CASH, CARD, THANK YOU
- **Extract as negative item**: DISCOUNT, COUPON, SAVINGS, -$X.XX
- Parser rules: regex patterns for ignored lines
- User can manually add discounts if parser misses them

**Example**:

```
MILK                    $4.99
BREAD                   $2.50
COUPON                  -$1.00  ← Extract as item: name="COUPON", total_cents=-100
SUBTOTAL                $6.49
TAX                     $0.52    ← Ignore
TOTAL                   $7.01     ← Ignore
```

---

### 4.3 Subtotal/Total Validation

**Question**: Do you want subtotal/total validation in MVP? Example: show a warning if sum(items) doesn't match detected subtotal/total.

**Recommendation**: ✅ **Yes, validation with warning (not error)**

**Rationale**:

- Catches parser errors
- Helps users spot missing items
- Warning (not error): user can still confirm if they want
- Good UX: "Items sum to $45.23, receipt shows $45.99. Missing $0.76?"

**Implementation**:

- Parser extracts detected TOTAL from receipt
- Backend calculates: `sum(item.total_cents)`
- Response includes: `validation: { items_total_cents, detected_total_cents, difference_cents, warning_message }`
- iOS shows warning banner if difference > $0.50

**Alternative Considered**: Hard error if mismatch

- ❌ Too strict (parser may miss items, user may want to proceed)
- ❌ Blocks legitimate use cases

---

### 4.4 Rounding Rules

**Question**: What rounding rules do you want? Always store money as cents; do you ever need fractional cents (probably no).

**Recommendation**: ✅ **Integer cents only, round to nearest cent**

**Rationale**:

- Matches current architecture (all money as `BigInteger` cents)
- No fractional cents in real-world receipts
- Simpler math, no precision issues
- Parser: `round(price * 100)` to cents

**Implementation**:

- Parser: extract price as float, convert to cents: `int(round(price * 100))`
- Validation: all `total_cents` must be integers
- No fractional cents in database

**Edge cases**:

- "3 for $10" → split as 3 items of $3.33 each (333 cents)
- Remainder goes to first item (deterministic)

---

### 4.5 Deterministic Parsing

**Question**: Should the parser be deterministic across runs? (Usually yes. Important for debugging and consistent UI.)

**Recommendation**: ✅ **Yes, fully deterministic**

**Rationale**:

- Same input → same output (critical for debugging)
- Consistent UI (items don't reorder on refresh)
- Testable (can write unit tests)
- User trust (predictable behavior)

**Implementation**:

- Sort items by line number (from OCR)
- If line numbers missing, sort by text (alphabetical)
- No random elements in parser
- Version parser: `parser_version` field in extraction

**Alternative Considered**: Non-deterministic (ML-based)

- ❌ Harder to debug
- ❌ Inconsistent UX
- ❌ Can't test reliably

---

## 5. Review/Edit/Confirm Workflow

### 5.1 Draft State Storage

**Question**: Do you want a "draft" state stored on the backend? Or keep draft only on iOS and send final items on confirm?

**Recommendation**: ✅ **Draft state on backend**

**Rationale**:

- User can switch devices (iPhone → iPad)
- Backend is source of truth (per architecture)
- Can resume editing later
- Better for collaboration (if multiple users edit later)

**Implementation**:

- New table: `receipt_draft_items`
  - `id`, `receipt_upload_id`, `name`, `total_cents`, `quantity`, `unit_price_cents`
  - `line_number`, `confidence`, `extracted_at`, `confirmed_at` (nullable)
- Status: `draft` → `confirmed` (when user confirms)
- On confirm: create `ShoppingItem` records, delete drafts

**Alternative Considered**: Draft only on iOS

- ❌ Lost if app crashes
- ❌ Can't sync across devices
- ❌ Backend can't validate until confirm

---

### 5.2 Edit Format

**Question**: How should edits be sent from iOS? Replace-all list (simple + robust) or patch per item (more complex)?

**Recommendation**: ✅ **Replace-all list (simple + robust)**

**Rationale**:

- Simpler to implement (one endpoint)
- Atomic operation (all or nothing)
- Easier to handle conflicts
- Matches mental model: "here's my final list"

**Implementation**:

- Endpoint: `PUT /receipt-extractions/{extraction_id}/draft-items`
- Body: `{ "items": [...] }` (full list)
- Backend: delete old drafts, create new ones
- Idempotent: same request = same result

**Alternative Considered**: PATCH per item

- ❌ More complex (multiple requests)
- ❌ Race conditions (concurrent edits)
- ❌ Harder to validate (partial state)

---

### 5.3 Confirm Behavior

**Question**: What happens on confirm? Create shopping_items immediately? Also auto-create shopping_item_splits? (or splits happen later when sharers set)

**Recommendation**: ✅ **Create shopping_items immediately, NO auto-splits**

**Rationale**:

- Items exist independently of splits
- User sets sharers later (per item or bulk)
- Matches current workflow: create items → set sharers
- Simpler: one step at a time

**Implementation**:

- Endpoint: `POST /receipt-extractions/{extraction_id}/confirm`
- Action: create `ShoppingItem` from confirmed drafts
- Delete draft items
- Return: list of created `ShoppingItem` IDs
- User then sets sharers via existing `/items/{item_id}/sharers` endpoint

**Alternative Considered**: Auto-create splits

- ❌ Assumes all items shared by all participants (often wrong)
- ❌ User has to undo splits (worse UX)
- ❌ More complex logic

---

### 5.4 Multiple Confirms

**Question**: Can the user confirm multiple times? If they reconfirm, do we overwrite items, create a new "revision", or reject?

**Recommendation**: ✅ **Reject reconfirm (idempotent: same draft = same result)**

**Rationale**:

- Prevents accidental duplicates
- Clear error: "Items already confirmed. Edit draft first."
- User must explicitly edit draft to reconfirm
- Idempotent: confirming same draft twice = no-op

**Implementation**:

- Check: if `confirmed_at IS NOT NULL`, reject with 409 Conflict
- Error: "Items already confirmed. Create new extraction to re-parse."
- Alternative: allow "re-extract" from same receipt (new extraction record)

**Alternative Considered**: Overwrite items

- ❌ Loses audit trail
- ❌ Confusing: "where did my items go?"
- ❌ Harder to debug

---

## 6. Auth & Permissions

### 6.1 Extraction Permissions

**Question**: Who is allowed to upload receipts and run extraction? You currently have "payer only" for receipt upload—does extraction/edit/confirm follow the same rule?

**Recommendation**: ✅ **Payer only for all extraction operations**

**Rationale**:

- Consistent with current model (payer uploads receipts)
- Payer is responsible for accuracy
- Prevents conflicts (multiple people editing)
- Matches user expectations

**Implementation**:

- All extraction endpoints: verify `requester_membership_id == session.paid_by_membership_id`
- Error: "Only the payer can extract/edit/confirm receipt items"
- View-only: all session members can view drafts/confirmed items

**Alternative Considered**: All members can edit

- ❌ Conflicts (who edited what?)
- ❌ Confusing ownership
- ❌ Harder to audit

---

### 6.2 Auditability

**Question**: Do you want auditability for receipt edits? Store who edited/confirmed and when?

**Recommendation**: ✅ **Yes, store editor and timestamps**

**Rationale**:

- Debugging: "Who confirmed this extraction?"
- Support: "When was this item edited?"
- Future: activity feed ("Alice confirmed receipt items")
- Low cost (just add fields)

**Implementation**:

- `receipt_draft_items`: `edited_by_membership_id`, `edited_at`
- `receipt_ocr_extractions`: `extracted_by_membership_id`, `extracted_at`, `confirmed_by_membership_id`, `confirmed_at`
- All timestamps in UTC

---

## 7. Idempotency & Concurrency

### 7.1 Idempotent Operations

**Question**: Should extraction creation and confirm be idempotent? (Recommended: yes, especially if iOS retries on poor network.)

**Recommendation**: ✅ **Yes, both idempotent**

**Rationale**:

- Matches existing pattern (expenses are idempotent)
- Network retries won't create duplicates
- Better UX (no "did it work?" uncertainty)

**Implementation**:

- Extraction: use `Idempotency-Key` header
- Confirm: use `Idempotency-Key` header
- Store in `idempotency_keys` table (existing pattern)
- Return cached response on duplicate

**Alternative Considered**: Not idempotent

- ❌ Duplicate extractions on retry
- ❌ User confusion ("why are there 2 extractions?")
- ❌ Inconsistent with rest of API

---

### 7.2 Concurrency

**Question**: What's the expected concurrency scenario? Multiple members editing the same receipt at once, or only the payer?

**Recommendation**: ✅ **Only payer edits (no concurrency issues)**

**Rationale**:

- Matches permission model (payer only)
- No conflicts (single editor)
- Simpler implementation (no locking needed)
- Better UX (clear ownership)

**Implementation**:

- No optimistic locking needed (single editor)
- If we add multi-editor later: add `version` field to drafts

**Future Consideration**: If we allow multiple editors

- Add `version` field to `receipt_draft_items`
- Optimistic locking on edits
- Conflict resolution: "Someone else edited. Refresh and try again."

---

## 8. Observability and Debugging

### 8.1 Parser Metadata

**Question**: Do you want to store "why the parser chose this line" metadata? Example: source_line, matched_price, excluded_reason, confidence.

**Recommendation**: ✅ **Yes, store parser metadata**

**Rationale**:

- Critical for debugging: "Why did parser extract this?"
- Improves parser over time (see what works)
- User support: "Parser missed item X because..."
- Low cost (JSONB field)

**Implementation**:

- `receipt_draft_items`: add `parser_metadata` (JSONB)

  ```json
  {
    "source_line": "MILK 2% GAL          $4.99",
    "matched_price": "$4.99",
    "confidence": 0.95,
    "excluded_reason": null,
    "parser_rule": "grocery_item_pattern"
  }
  ```

- Helps debug: "Why was this line excluded?"

---

### 8.2 Re-run Parsing

**Question**: Do you want a "re-run parsing" endpoint for the same raw_text? Useful when you improve rules.

**Recommendation**: ✅ **Yes, re-run endpoint**

**Rationale**:

- Parser improvements: re-parse old receipts with new rules
- User support: "Try parsing again with improved parser"
- Testing: validate parser improvements on real data

**Implementation**:

- Endpoint: `POST /receipt-extractions/{extraction_id}/re-parse`
- Body: `{ "parser_version": "v2" }` (optional, defaults to latest)
- Action: create new extraction with same `receipt_upload_id`
- Keep old extraction (for comparison)
- User can compare: "Old parse vs new parse"

**Alternative Considered**: Only parse once

- ❌ Can't improve old receipts
- ❌ User stuck with bad parse

---

## 9. Future-Proofing

### 9.1 Server-Side OCR

**Question**: Do you plan to add server-side OCR later (Textract/Google Vision)? If yes, we should store provider and keep the pipeline provider-agnostic.

**Recommendation**: ✅ **Yes, design for multiple providers**

**Rationale**:

- iOS Vision may not be available on all devices
- Server-side OCR can be more accurate
- Fallback: if iOS OCR fails, try server-side
- Provider-agnostic: easy to switch/add providers

**Implementation**:

- `receipt_ocr_extractions`: add `ocr_provider` field
  - Values: `"apple_vision"`, `"aws_textract"`, `"google_vision"`, `"manual"`
- Parser is provider-agnostic (works with any OCR output)
- Future: add server-side OCR service
- iOS can choose: "Use server OCR" option

**Schema**:

```python
ocr_provider: Mapped[str] = mapped_column(String(50), nullable=False)
# Values: "apple_vision", "aws_textract", "google_vision", "manual"
```

---

### 9.2 Item Categories & UPCs

**Question**: Do you plan to support item categories or UPC codes later? If yes, draft item schema might need extra fields.

**Recommendation**: ✅ **Add optional fields now (nullable)**

**Rationale**:

- Easy to add now (nullable fields)
- Hard to add later (migration, data backfill)
- Categories: useful for analytics ("spent $X on groceries")
- UPCs: useful for item matching ("same item from different stores")

**Implementation**:

- `receipt_draft_items`: add `category` (nullable String), `upc` (nullable String)
- Parser: extract if available (most receipts don't have UPCs)
- User can fill in category during review
- Future: auto-categorize based on name (ML)

**Schema**:

```python
category: Mapped[str | None] = mapped_column(String(50), nullable=True)
upc: Mapped[str | None] = mapped_column(String(20), nullable=True)
```

---

## 10. Implementation Priority

### Phase 1: MVP (Core Functionality)

1. ✅ iOS OCR extraction → Backend storage
2. ✅ Basic parser (grocery receipts, name + price)
3. ✅ Draft items storage
4. ✅ Edit draft items (replace-all)
5. ✅ Confirm → create ShoppingItems
6. ✅ Payer-only permissions

### Phase 2: Polish

1. ✅ Subtotal/total validation
2. ✅ Parser metadata storage
3. ✅ Re-parse endpoint
4. ✅ S3 migration (from local filesystem)

### Phase 3: Advanced

1. ✅ Server-side OCR (Textract/Google Vision)
2. ✅ Item categories
3. ✅ UPC extraction
4. ✅ Multi-receipt aggregation

---

## 11. Database Schema Changes

### New Tables

```sql
-- Receipt OCR Extractions
CREATE TABLE receipt_ocr_extractions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receipt_upload_id UUID NOT NULL REFERENCES receipt_uploads(id) ON DELETE CASCADE,
    ocr_provider VARCHAR(50) NOT NULL,  -- 'apple_vision', 'aws_textract', etc.
    raw_ocr_data JSONB NOT NULL,  -- Full iOS payload
    parser_version VARCHAR(20) NOT NULL,  -- 'v1', 'v2', etc.
    extracted_by_membership_id UUID NOT NULL,
    extracted_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    confirmed_at TIMESTAMP WITH TIME ZONE,
    confirmed_by_membership_id UUID,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Receipt Draft Items
CREATE TABLE receipt_draft_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    extraction_id UUID NOT NULL REFERENCES receipt_ocr_extractions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    total_cents BIGINT NOT NULL,
    quantity INTEGER,
    unit_price_cents BIGINT,
    line_number INTEGER,  -- From OCR
    confidence DECIMAL(3,2),  -- 0.00 to 1.00
    parser_metadata JSONB,  -- Why parser chose this
    category VARCHAR(50),
    upc VARCHAR(20),
    edited_by_membership_id UUID,
    edited_at TIMESTAMP WITH TIME ZONE,
    confirmed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Update ReceiptUpload
ALTER TABLE receipt_uploads 
ADD COLUMN superseded_by_id UUID REFERENCES receipt_uploads(id);
```

---

## 12. API Endpoints

### New Endpoints

```
POST   /receipt-uploads/{upload_id}/extract
       Extract items from OCR data (idempotent)

GET    /receipt-extractions/{extraction_id}
       Get extraction with draft items

PUT    /receipt-extractions/{extraction_id}/draft-items
       Replace all draft items (idempotent)

POST   /receipt-extractions/{extraction_id}/confirm
       Confirm draft items → create ShoppingItems (idempotent)

POST   /receipt-extractions/{extraction_id}/re-parse
       Re-run parser with improved rules
```

---

## 13. Decision Summary

| Decision | Recommendation | Status |
|----------|---------------|--------|
| MVP Success | Draft + user fixes | ⚠️ Pending |
| Receipts per session | Multiple | ⚠️ Pending |
| Currency | USD only (MVP) | ⚠️ Pending |
| Store types | Major grocery chains | ⚠️ Pending |
| iOS format | Array of lines with metadata | ⚠️ Pending |
| Store OCR output | Yes | ⚠️ Pending |
| Max receipt size | 100 lines, 10KB | ⚠️ Pending |
| Upload flow | Backend → S3 | ⚠️ Pending |
| Receipt privacy | Private, presigned URLs | ⚠️ Pending |
| Delete/replace | Keep old (audit) | ⚠️ Pending |
| Draft fields | name + total (req), qty/unit (opt) | ⚠️ Pending |
| Non-item lines | Ignore totals, extract discounts | ⚠️ Pending |
| Total validation | Warning (not error) | ⚠️ Pending |
| Rounding | Integer cents | ⚠️ Pending |
| Deterministic | Yes | ⚠️ Pending |
| Draft storage | Backend | ⚠️ Pending |
| Edit format | Replace-all | ⚠️ Pending |
| Confirm behavior | Create items, no splits | ⚠️ Pending |
| Multiple confirms | Reject (idempotent) | ⚠️ Pending |
| Permissions | Payer only | ⚠️ Pending |
| Auditability | Yes (who/when) | ⚠️ Pending |
| Idempotency | Yes (both) | ⚠️ Pending |
| Concurrency | Payer only (no conflicts) | ⚠️ Pending |
| Parser metadata | Yes | ⚠️ Pending |
| Re-run parsing | Yes | ⚠️ Pending |
| Server-side OCR | Design for multiple providers | ⚠️ Pending |
| Categories/UPCs | Add nullable fields | ⚠️ Pending |

---

## Next Steps

1. **Review this document** - Approve or modify each decision
2. **Update recommendations** - Mark any changes needed
3. **Create implementation plan** - Break down into tasks
4. **Start Phase 1** - Implement MVP functionality

---

*Document created: January 2025*
*Status: Awaiting product review and approval*
