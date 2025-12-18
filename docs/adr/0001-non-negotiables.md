# ADR 0001: Early Decisions (Non-Negotiable)

- Money stored as integer cents (`bigint`); never float/decimal.
- Expense creation is atomic (single DB transaction).
- Settlement results are immutable snapshots; new batch when recalculated; only status/void reason mutable.
- Idempotency keys required on all write endpoints; uniqueness `(endpoint, user_id, request_hash)`.
- All timestamps stored/transmitted as UTC ISO-8601.

Status: Accepted  
Context: Foundation for financial correctness and auditability. Changing any item would require data migration and client/server contract shifts.
