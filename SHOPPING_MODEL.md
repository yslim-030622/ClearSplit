# Shopping Model Documentation

## Overview

ClearSplit has been refactored to support a **roommates grocery shopping app** workflow. The system now allows users to:

1. Create **Shopping Sessions** (grocery trips) within a Group (household)
2. Upload receipt images
3. Manually add line items with prices
4. Select which participants share each item
5. Automatically compute **equal splits** (1/n only) with deterministic remainder distribution

The original expense-tracking functionality remains intact. This shopping model runs alongside it.

---

## Core Concepts

### Shopping Session (aka "Trip")
- Represents a single grocery shopping trip (e.g., "Costco Jan 7")
- Has exactly **one payer/creator** who:
  - Creates the session
  - Selects participants (subset of group members)
  - Uploads receipts
  - Adds items and assigns sharers
- Belongs to a **Group** (household)
- Currency is **fixed to USD** for MVP

### Participants
- A shopping session selects which group members participated in that trip
- Only participants can be selected as sharers for items
- The payer must be a participant

### Shopping Items
- Line items from the receipt (e.g., "Milk 2 gallons", "Tax")
- Each item has:
  - Name
  - Quantity (≥ 1)
  - Unit price (optional, in cents)
  - Total price (required, in cents)
- For each item, the payer selects sharers (must be participants)
- System computes **equal split** (1/n) among sharers

### Equal Split Logic
- Total is divided equally among selected sharers
- Remainder cents are distributed deterministically:
  - Sharers sorted by UUID string
  - First `remainder` sharers get `base_share + 1` cent
  - Rest get `base_share`
- Example: $10.00 (1000 cents) split 3 ways → [334, 333, 333]

### Taxes and Fees
- Handled as normal line items (e.g., "Sales Tax")
- Payer selects who shares the tax/fee
- System splits equally

---

## Data Model

### Backend (SQLAlchemy)

#### `shopping_sessions` table
```sql
id                      UUID PRIMARY KEY
group_id                UUID → groups.id (CASCADE DELETE)
title                   TEXT NOT NULL
shopping_date           DATE (nullable)
currency                VARCHAR(3) DEFAULT 'USD'
paid_by_membership_id   UUID (payer, must be group member)
created_at              TIMESTAMP
```

#### `shopping_session_participants` table
```sql
id              UUID PRIMARY KEY
session_id      UUID → shopping_sessions.id (CASCADE DELETE)
membership_id   UUID (must belong to same group)
created_at      TIMESTAMP
UNIQUE (session_id, membership_id)
```

#### `receipt_uploads` table
```sql
id              UUID PRIMARY KEY
session_id      UUID → shopping_sessions.id (CASCADE DELETE)
storage_key     TEXT (file path/key)
content_type    VARCHAR(100) (e.g., 'image/jpeg')
created_at      TIMESTAMP
```

#### `shopping_items` table
```sql
id                  UUID PRIMARY KEY
session_id          UUID → shopping_sessions.id (CASCADE DELETE)
name                TEXT NOT NULL
quantity            INTEGER DEFAULT 1, ≥ 1
unit_price_cents    BIGINT (nullable, ≥ 0)
total_cents         BIGINT NOT NULL, > 0
created_at          TIMESTAMP
CHECK: quantity >= 1
CHECK: unit_price_cents IS NULL OR unit_price_cents >= 0
CHECK: total_cents > 0
```

#### `shopping_item_splits` table
```sql
id              UUID PRIMARY KEY
item_id         UUID → shopping_items.id (CASCADE DELETE)
membership_id   UUID (must be session participant)
share_cents     BIGINT NOT NULL, ≥ 0
created_at      TIMESTAMP
UNIQUE (item_id, membership_id)
CHECK: share_cents >= 0
INVARIANT: SUM(share_cents) = shopping_items.total_cents
```

### iOS (Swift Models)

Key models defined in `ShoppingModels.swift`:
- `ShoppingSession` — session details with participants, receipts, items
- `ShoppingSessionParticipant` — join record
- `ReceiptUpload` — receipt metadata
- `ShoppingItem` — line item with splits
- `ShoppingItemSplit` — per-person share

---

## API Endpoints

All endpoints require authentication. Only group members can view; only the payer can mutate.

### Shopping Sessions

#### `POST /groups/{group_id}/shopping-sessions`
Create a new shopping session.

**Request:**
```json
{
  "title": "Costco Trip",
  "shopping_date": "2025-01-07",
  "paid_by": "<membership_id>"
}
```

**Response:** `201 Created` + `ShoppingSessionRead`

---

#### `GET /groups/{group_id}/shopping-sessions`
List all shopping sessions for a group.

**Response:** `200 OK` + array of `ShoppingSessionRead`

---

#### `GET /shopping-sessions/{session_id}`
Get session details (includes participants, receipts, items with splits).

**Response:** `200 OK` + `ShoppingSessionRead`

---

#### `PUT /shopping-sessions/{session_id}/participants`
Set/replace participants (payer only).

**Request:**
```json
{
  "participant_membership_ids": ["<uuid>", "<uuid>"]
}
```

**Response:** `200 OK` + updated `ShoppingSessionRead`

---

### Receipts

#### `POST /shopping-sessions/{session_id}/receipt`
Upload a receipt image (payer only).

**Request:** `multipart/form-data` with `file` field

**Response:** `201 Created` + `ReceiptUploadRead`

---

### Shopping Items

#### `POST /shopping-sessions/{session_id}/items`
Create a shopping item (payer only).

**Request:**
```json
{
  "name": "Milk (2 gallons)",
  "quantity": 2,
  "unit_price_cents": 399,
  "total_cents": 798  // optional if unit_price * quantity provided
}
```

Or for tax/fee:
```json
{
  "name": "Sales Tax",
  "total_cents": 125
}
```

**Response:** `201 Created` + `ShoppingItemRead`

---

#### `PUT /items/{item_id}/sharers`
Set/replace sharers for an item (payer only). System computes equal splits.

**Request:**
```json
{
  "membership_ids": ["<uuid>", "<uuid>", "<uuid>"]
}
```

**Response:** `200 OK` + `SharersSetResponse` with computed splits
```json
{
  "item_id": "<uuid>",
  "total_cents": 1000,
  "splits": [
    {"id": "<uuid>", "item_id": "<uuid>", "membership_id": "<uuid>", "share_cents": 334},
    {"id": "<uuid>", "item_id": "<uuid>", "membership_id": "<uuid>", "share_cents": 333},
    {"id": "<uuid>", "item_id": "<uuid>", "membership_id": "<uuid>", "share_cents": 333}
  ]
}
```

---

## Authorization Rules

| Action | Who Can Do It |
|--------|---------------|
| View shopping session | Any group member |
| Create shopping session | Any group member (becomes payer) |
| Set participants | Payer only |
| Upload receipt | Payer only |
| Add item | Payer only |
| Set sharers | Payer only |

Non-payer group members can **view** everything but cannot edit.

---

## iOS User Flow

1. **Home / Groups List** → Select a group
2. **Shopping Sessions List** → View all trips for that group
3. **Tap "+"** → Create new shopping session (title, optional date)
4. **Session Detail**:
   - View summary (total, participants, receipts, items)
   - If payer: **Set Participants**, **Upload Receipt**, **Add Item**
5. **Add Item**:
   - Enter name, quantity, unit price or total
   - Select sharers (multi-select from participants)
   - System computes and displays equal splits
   - Save → item appears in session detail

---

## Backend Service Layer

Key functions in `app/services/shopping.py`:

- `create_shopping_session()` — validates payer membership, creates session
- `set_session_participants()` — replaces participants, enforces payer-only
- `upload_receipt()` — saves image to local storage (abstracted for future S3)
- `create_shopping_item()` — creates item record
- `set_item_sharers()` — computes equal splits, replaces splits atomically
- `calculate_equal_splits()` — deterministic remainder distribution

---

## Testing

### Backend Tests (`test_shopping.py`)

Comprehensive tests cover:
- Session creation and authorization
- Participant validation (must belong to group)
- Item creation with unit price and total-only modes
- Equal split computation with remainder handling
- Sharers must be session participants
- Non-payer access control (cannot mutate)
- Receipt upload (multipart)

Run tests:
```bash
cd backend
make test
```

### iOS Tests

Manual testing recommended for MVP. Key scenarios:
- Create session, set participants, add items, select sharers
- Upload receipt from photo library
- View computed splits for each item
- Verify non-payer sees read-only UI

---

## Migration

Run the new migration to create shopping tables:

```bash
cd backend
alembic upgrade head
```

This applies migration `20250107_0002_add_shopping_tables.py` which creates:
- `shopping_sessions`
- `shopping_session_participants`
- `receipt_uploads`
- `shopping_items`
- `shopping_item_splits`

---

## File Storage (Receipts)

For MVP, receipts are stored in local filesystem at `/tmp/clearsplit_receipts/{session_id}/{uuid}.jpg`.

The storage layer is abstracted in `ReceiptStorage` class, making it easy to switch to S3 or similar later.

---

## Non-Goals (Out of Scope for MVP)

- ❌ OCR / GPT receipt extraction
- ❌ Multi-currency support
- ❌ Multi-payer or split payments
- ❌ Custom/weighted splits (only equal 1/n)
- ❌ Participant editing rights / approvals
- ❌ Item disputes or reconciliation flows
- ❌ Receipt total vs items total validation

---

## Example Workflow

**Alice, Bob, and Carol are roommates in "Home" group.**

1. Alice goes to Costco and pays for groceries.
2. Alice creates a shopping session: "Costco Trip"
3. Alice sets participants: Alice, Bob, Carol
4. Alice uploads receipt image
5. Alice adds items:
   - "Milk 2 gallons" → $7.98 → shared by Alice, Bob
   - "Vegan Snacks" → $5.00 → shared by Alice, Carol
   - "Shared Cereal" → $10.00 → shared by Alice, Bob, Carol
   - "Sales Tax" → $1.25 → shared by Alice, Bob, Carol

System computes splits:
- Milk: Alice $3.99, Bob $3.99
- Vegan Snacks: Alice $2.50, Carol $2.50
- Cereal: Alice $3.34, Bob $3.33, Carol $3.33 (remainder to Alice)
- Tax: Alice $0.42, Bob $0.42, Carol $0.41 (remainder distributed)

**Result:**
- Alice paid: $24.23
- Alice's share: $10.25
- Bob's share: $7.74
- Carol's share: $6.24

Bob owes Alice $7.74, Carol owes Alice $6.24.

(Future: settlement suggestions can be generated from these balances.)

---

## Summary

The shopping model provides a **roommates grocery receipt splitting** experience:
- **One payer** per session
- **Equal splits only** (1/n)
- **Deterministic remainder** distribution
- **Payer-controlled** item entry and sharer selection
- **Read-only** for other group members
- **USD fixed** for MVP
- **Production-grade** backend with tests, migrations, and authorization

This refactor maintains the existing expense system while introducing a new, focused workflow for grocery shopping among roommates.

