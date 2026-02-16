# Project Overview

## What ClearSplit Is

ClearSplit helps a group track shared expenses and shopping sessions, then settle up with the smallest practical number of transfers.

The system has two main user experiences:
- enter shared expenses and see live balances
- run collaborative shopping sessions with receipt upload and optional OCR-assisted item entry

## Current Feature Set

### Accounts and identity

- signup with `username`, `email`, `password`, `first_name`, `last_name`
- login using either username or email as `identifier`
- JWT access token + rotating refresh token flow
- normalized identity matching for case-insensitive email/username behavior

### Groups and membership

- create and list groups
- owner/member/viewer roles
- owner-only member add
- invite preview endpoint to verify user existence before adding

### Expenses and balances

- create expenses with equal split logic
- per-group expense history
- live group balances (not just static snapshots)
- settlement suggestions generated from current net balances

### Settlement payments

- create pending or auto-confirmed settlement payments
- receiver/owner confirmation workflow
- payment history per group
- legacy settlement status endpoint still supported

### Shopping flow

- create and manage shopping sessions
- configure participants per session
- add/edit/delete items
- assign item sharers with deterministic equal split remainder handling
- finalize sessions
- automatic `settled` transition when covered balances are fully paid

### Receipts and OCR

- one receipt per shopping session
- participant-only receipt upload
- uploader-only receipt deletion and OCR trigger
- OCR extraction pipeline with image safety checks and timeout
- extracted receipt items retrievable by any group member

### Friends

- friend request send/accept/decline
- incoming/outgoing request lists
- friend list and unfriend flow

## Non-goals (Current)

As implemented today:
- no push notification pipeline
- no web client
- no background job queue for OCR (OCR runs in request lifecycle with a timeout)
- no multi-currency conversion logic in settlement engine
