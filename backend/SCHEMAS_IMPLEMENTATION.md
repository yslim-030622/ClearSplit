# Pydantic Schemas Implementation Summary

## Files Created

1. `app/schemas/base.py` - Base schema classes and mixins
2. `app/schemas/user.py` - User schemas (Create, Update, Read)
3. `app/schemas/group.py` - Group schemas (Create, Update, Read)
4. `app/schemas/membership.py` - Membership schemas (Create, Update, Read)
5. `app/schemas/expense.py` - Expense and ExpenseSplit schemas
6. `app/schemas/settlement.py` - SettlementBatch and Settlement schemas
7. `app/schemas/__init__.py` - Clean exports of all schemas

## Schema Design Principles

### Request vs Response Schemas

**Request Schemas (Create/Update):**
- **Create schemas**: Fields required to create a new entity
  - No server-generated fields (id, created_at, etc.)
  - Client-provided data only
  - Validation rules for data integrity
- **Update schemas**: All fields optional (PATCH semantics)
  - Only include fields that can be updated
  - Immutable fields (id, created_at) excluded
  - Version field excluded (handled separately for optimistic locking)

**Response Schemas (Read):**
- Include all fields that clients need
- Server-generated fields included (id, timestamps, version)
- Optional nested relationships for convenience (e.g., `splits` in ExpenseRead)
- Stable structure for mobile client versioning

### Type Mappings

- **UUID**: Python `UUID` type (serialized as string in JSON)
- **Cents**: Python `int` type (no floats/decimals per non-negotiables)
- **Timestamps**: Python `datetime` type (ISO-8601 format in JSON)
- **Dates**: Python `date` type
- **Enums**: Python enum classes (serialized as string values)

## Schema Details by Entity

### User Schemas

**UserRead:**
- Minimal fields: `id`, `email` (per requirements)
- No password hash exposed

**UserCreate:**
- `email`: EmailStr with validation
- `password`: String with min_length=8

**UserUpdate:**
- All fields optional
- Email and password can be updated

### Group Schemas

**GroupRead:**
- All fields including timestamps and version
- Currency code included

**GroupCreate:**
- `name`: Required, 1-255 characters
- `currency`: Optional, defaults to "USD", validated to uppercase

**GroupUpdate:**
- All fields optional
- Currency validated to uppercase if provided

### Membership Schemas

**MembershipRead:**
- All membership fields
- Optional `user` nested object for convenience

**MembershipCreate:**
- `user_id`: Required
- `role`: Optional, defaults to MEMBER

**MembershipUpdate:**
- Only `role` can be updated (per constraints)

### Expense Schemas

**ExpenseRead:**
- All expense fields including timestamps and version
- Optional `splits` nested list for convenience

**ExpenseSplitRead:**
- Split details with membership_id and share_cents

**ExpenseCreate:**
- All expense fields except server-generated ones
- `splits`: Required list of ExpenseSplitCreate
- **Validation**: Splits must sum to amount_cents (cross-field validation)
- Currency validated to uppercase

**ExpenseSplitCreate:**
- `membership_id`: Required
- `share_cents`: Required, >= 0

**ExpenseUpdate:**
- All fields optional (PATCH semantics)
- If both `amount_cents` and `splits` provided, splits must sum to amount_cents

### Settlement Schemas

**SettlementBatchRead:**
- All batch fields including timestamps and version
- Optional `settlements` nested list for convenience
- `voided_reason` included if present

**SettlementRead:**
- All settlement fields
- `from_membership` and `to_membership` as UUIDs

**SettlementBatchCreate:**
- Minimal: only `group_id`
- Note: Typically created by settlement engine, not clients

**SettlementBatchUpdate:**
- Only `status` and `voided_reason` (per immutability constraints)
- Status changes and voiding only

**SettlementUpdate:**
- Only `status` can be updated (per immutability constraints)

## Validation Rules

### Field-Level Validation

- **Email**: `EmailStr` type for email validation
- **Amounts**: `gt=0` for expenses/settlements, `ge=0` for splits
- **Currency**: Uppercase validation, 3-character length
- **Strings**: Min/max length constraints where appropriate
- **UUIDs**: Validated as UUID type

### Cross-Field Validation

- **Expense splits**: Must sum to `amount_cents` (using `model_validator`)
- Applied in both Create and Update schemas

## Versioning Considerations

Schemas are designed to be stable for mobile clients:

1. **Additive changes only**: New fields added as optional
2. **No breaking changes**: Existing fields maintain same types
3. **Optional nested objects**: Relationships included optionally to avoid breaking changes
4. **Clear field descriptions**: Help clients understand field purposes
5. **Enum stability**: Enum values are strings, backward compatible

## Usage Notes

### Request Schemas
- Use `Create` schemas for POST endpoints
- Use `Update` schemas for PATCH/PUT endpoints
- Validation happens automatically via Pydantic

### Response Schemas
- Use `Read` schemas for GET endpoints
- Can be constructed from SQLAlchemy models using `from_attributes=True`
- Optional nested relationships can be populated via `include` parameter pattern

### Example Usage

```python
# Create expense
expense_data = ExpenseCreate(
    title="Dinner",
    amount_cents=5000,
    currency="USD",
    paid_by=membership_id,
    expense_date=date.today(),
    splits=[
        ExpenseSplitCreate(membership_id=member1_id, share_cents=2500),
        ExpenseSplitCreate(membership_id=member2_id, share_cents=2500),
    ]
)

# Response from model
expense_read = ExpenseRead.model_validate(expense_model)
```

## Notes on What Belongs in Request vs Response

### Request Schemas (Create/Update)
- **Include**: Client-provided data, validation rules
- **Exclude**: Server-generated fields (id, timestamps, version)
- **Exclude**: Computed fields (total_settlements in SettlementBatch)
- **Exclude**: Relationships (added separately if needed)

### Response Schemas (Read)
- **Include**: All fields clients need to display/use
- **Include**: Server-generated fields (id, timestamps, version)
- **Include**: Optional nested relationships for convenience
- **Exclude**: Sensitive data (password hashes)
- **Exclude**: Internal-only fields (if any)

### Special Cases

1. **Expense splits**: Included in Create (required), optional in Read (for convenience)
2. **Settlement batches**: Create is minimal (engine-generated), Read includes all details
3. **Membership user**: Optional in Read for convenience, not in Create/Update
4. **Version fields**: In Read for optimistic locking, not in Create/Update

