# iOS Reference

## App Structure

The iOS client is implemented in SwiftUI and organized by feature slices.

Key folders under `ios/ClearSplit/Sources/ClearSplit`:

- `State/`: shared app state (`AppState`)
- `Networking/`: `APIClient` and domain service wrappers
- `Models/`: Codable request/response and UI data models
- `ViewModels/`: screen-level orchestration
- `Views/`: feature screens and reusable UI components
- `DesignSystem/`: tokens, colors, button/card styles
- `Storage/`: token persistence (`KeychainService`)

## AppState Responsibilities

`AppState` is the central coordinator for:

- session bootstrap and auth lifecycle
- loading groups, members, expenses, balances, payments
- shopping sessions, items, sharers, receipts, OCR extraction
- mutating operations that keep local screen state in sync

On startup:
1. check stored tokens
2. call `/auth/me`
3. load groups

If `/auth/me` fails, local tokens are cleared and user is logged out.

## Networking Layer

### APIConfig

- default base URL: `http://127.0.0.1:8000`
- override via Info.plist key: `API_BASE_URL`
- real-device hint logic warns against loopback URLs on device

### APIClient behavior

- injects bearer token for authenticated requests
- on `401`, refreshes tokens once and retries request
- refresh flow is coordinated to avoid duplicate simultaneous refresh calls
- uses snake_case conversion for request/response keys
- date decoder accepts multiple ISO8601 variants used by backend responses
- supports both JSON requests and multipart upload (receipt upload)

## Feature Coverage in UI

### Authentication

- login screen uses username or email identifier
- signup captures username, email, password, first/last name

### Group and members

- groups tab lists current groups
- create group flow
- group detail loads members, balances, expenses, shopping sessions
- member invite flow supports preview before add

### Expenses and balances

- create equal-split expenses
- show live per-membership balances
- generate and act on settlement suggestions
- show settlement payment history

### Shopping sessions

- create/list/open sessions
- manage participants
- add/edit/delete items
- set per-item sharers
- upload and delete receipt
- trigger and review OCR extracted items
- finalize session and reflect settlement status changes

### Friends

- send friend request by identifier or user ID
- incoming/outgoing request lists
- accept/decline/remove friendship

## Build, Test, Lint Scripts

From `ios/ClearSplit`:

```bash
./scripts/ios_build.sh
./scripts/ios_test.sh unit
./scripts/ios_test.sh ui
./scripts/ios_test.sh all
./scripts/ios_lint.sh
./scripts/ios_archive.sh
```

Script behavior:
- deterministic DerivedData/result bundle locations under `.build/`
- simulator destination auto-resolution when not explicitly provided
- code signing disabled for CI-oriented build/test/archive scripts

## Local Runtime Notes

- Simulator can use default loopback URL.
- Real devices require LAN-reachable backend URL in `API_BASE_URL`.
- If you see immediate network failures on device, verify both backend bind host and local firewall settings.
