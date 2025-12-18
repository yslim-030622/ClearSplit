# ClearSplit Database Schema (MVP1)

Primary keys are UUIDs (safer for client-generated IDs and multi-env merges). Monetary values use `bigint` cents. All timestamps are `timestamptz` UTC. Expenses and settlement batches carry `version` for optimistic locking. Settlement batches are immutable snapshots; only status/void reason may change.

## Integrity Highlights
- Membership roles constrained via enum; one membership per (group, user). Composite uniques on (group_id, id) enable FK checks that paid_by/splits/settlements belong to the same group.
- Expense splits enforce `SUM(share_cents) = expenses.amount_cents` with a deferred constraint trigger; rejects inconsistent writes at commit.
- Settlements tie to group via composite FKs; prevent cross-group transfers.
- Idempotency keys unique on `(endpoint, user_id, request_hash)`; cleanup job should purge keys older than 30–90 days per SLA. Expect clients to send `Idempotency-Key` header; backend canonicalizes request body to compute `request_hash`.
- `amount_cents > 0`, `share_cents >= 0`. All money columns are `bigint`.
- `updated_at` maintained via DB triggers to avoid app-layer drift.

## Representative Queries
Q1) List group expenses  
```sql
SELECT e.id, e.title, e.amount_cents, e.currency, e.expense_date, e.created_at,
       p.user_id AS paid_by_user
FROM expenses e
JOIN memberships p ON p.id = e.paid_by
WHERE e.group_id = $1
ORDER BY e.expense_date DESC, e.created_at DESC;
```

Q2) Fetch splits for an expense  
```sql
SELECT es.membership_id, m.user_id, es.share_cents
FROM expense_splits es
JOIN memberships m ON m.id = es.membership_id
WHERE es.expense_id = $1;
```

Q3) Latest settlement batch for a group  
```sql
SELECT sb.*
FROM settlement_batches sb
WHERE sb.group_id = $1
ORDER BY sb.created_at DESC
LIMIT 1;
```

Q4) Settlements for a batch  
```sql
SELECT s.id, s.from_membership, fm.user_id AS from_user,
       s.to_membership, tm.user_id AS to_user,
       s.amount_cents, s.status, s.created_at
FROM settlements s
JOIN memberships fm ON fm.id = s.from_membership
JOIN memberships tm ON tm.id = s.to_membership
WHERE s.batch_id = $1;
```

Q5) Per-user net balances (paid - owed)  
```sql
WITH paid AS (
  SELECT e.paid_by AS membership_id, SUM(e.amount_cents) AS paid_cents
  FROM expenses e
  WHERE e.group_id = $1
  GROUP BY e.paid_by
),
owed AS (
  SELECT es.membership_id, SUM(es.share_cents) AS owed_cents
  FROM expenses e
  JOIN expense_splits es ON es.expense_id = e.id
  WHERE e.group_id = $1
  GROUP BY es.membership_id
)
SELECT m.user_id,
       COALESCE(p.paid_cents,0) - COALESCE(o.owed_cents,0) AS net_cents
FROM memberships m
LEFT JOIN paid p ON p.membership_id = m.id
LEFT JOIN owed o ON o.membership_id = m.id
WHERE m.group_id = $1;
```

## Alembic Migration Plan
1. Create extensions `uuid-ossp`, `citext`; create enums `membership_role`, `settlement_status`.
2. Tables: `users`, `groups`.
3. `memberships` (with uniques on (group_id, user_id) and (group_id, id)).
4. `expenses` (composite FK to memberships for paid_by) and uniques on (id, group_id).
5. `expense_splits` (composite FKs tying to expense and membership within the same group).
6. `settlement_batches` and `settlements` (composite FKs on group/batch/memberships).
7. `activity_log`, `idempotency_keys`.
8. Indexes.
9. Trigger functions: `set_updated_at`, `enforce_expense_split_sum`; constraint trigger creation.

## Assumptions
- `citext` is available (Postgres standard extension) for case-insensitive emails.
- Default currency is USD per group; expenses can override currency. FX handling can be added with an FX rates table and additional currency columns without primary key changes.
- Activity log is schema-light via `metadata jsonb`; app will standardize shapes.
- Idempotency retention handled by scheduled job.

## Extensibility Notes
- Unequal or custom splits already supported by `expense_splits.share_cents`.
- Receipts: add `expense_attachments(expense_id, url, content_type, uploaded_at, uploaded_by)` without changing core tables.
- Multi-currency: add `fx_rates` and per-expense settlement currency/amount columns; balances computed in chosen ledger currency.
- Settlement immutability: batches remain snapshots; to reflect expense edits, mark prior batch `voided` and create a new batch.
