# iOS Reference

## Stack and Pattern

- SwiftUI UI layer
- MVVM viewmodels
- `AppState` as global orchestration/state container
- Custom `APIClient` for HTTP + auth refresh logic
- Keychain-based token storage

Primary active code location:

- `ios/ClearSplit/Sources/ClearSplit/`

## App Composition

### Entry and Root Flow

- App entrypoint: `ios/ClearSplit/ClearSplit/ClearSplit/ClearSplitApp.swift`
- Root router: `ios/ClearSplit/Sources/ClearSplit/RootView.swift`

Root behavior:

1. If cached tokens exist, bootstrap with `/auth/me`.
2. On success, show group list.
3. On missing/invalid auth, show login.

### Global State (`AppState`)

`ios/ClearSplit/Sources/ClearSplit/State/AppState.swift` coordinates:

- auth session lifecycle
- groups, memberships, expenses, settlements caches
- live balances cache and settlement payment history cache
- shopping sessions and receipt interactions
- optimistic updates plus refresh calls after writes

`AppState` depends on:

- `AuthService`
- `GroupsService`
- `ShoppingService`
- shared `APIClient`

### Networking Layer

| File | Role |
| --- | --- |
| `Networking/APIClient.swift` | Generic request builder, date decoding, auth header injection, refresh-on-401 retry, upload helper. |
| `Networking/AuthService.swift` | login/signup/me/refresh endpoints. |
| `Networking/GroupsService.swift` | groups list endpoint. |
| `Networking/ShoppingService.swift` | shopping sessions, participants, receipt upload/download/extract, item/sharer endpoints. |
| `Networking/SettlementService.swift` | live balances, payment create/confirm/history, legacy mark-paid endpoint. |
| `Storage/KeychainService.swift` | token persistence under `com.clearsplit.auth`. |
| `Config/APIConfig.swift` | base URL from `API_BASE_URL` Info.plist key or localhost fallback. |

### Domain Models

Main Codable model groups:

- `Models/AuthModels.swift`
- `Models/GroupModels.swift`
- `Models/ExpenseModels.swift`
- `Models/SettlementModels.swift`
- `Models/ShoppingModels.swift`
- `Models/ExtractedItemModel.swift` (legacy/local receipt review structure)

Models are shaped to backend snake_case payloads through explicit coding keys and `convertFromSnakeCase`.

### Screen and ViewModel Responsibilities

| Feature | Views | ViewModels |
| --- | --- | --- |
| Auth | `Views/LoginView.swift`, `Views/SignUpView.swift` | `LoginViewModel`, `SignUpViewModel` |
| Groups | `Views/GroupsListView.swift`, `Views/GroupDetailView.swift`, `Views/CreateGroupView.swift` | `GroupsViewModel` |
| Balances & settlement | `Views/BalancesSettlementView.swift` | state-driven via `AppState` |
| Shopping sessions | `Views/ShoppingSessionsListView.swift`, `Views/CreateShoppingSessionView.swift`, `Views/ShoppingSessionDetailView.swift` | `ShoppingSessionsViewModel`, `CreateShoppingSessionViewModel`, `ShoppingSessionDetailViewModel` |
| Item creation | `Views/AddItemSheet.swift` + form components | `AddItemViewModel` |
| Receipt upload/review | `Views/ReceiptUploadView.swift`, `Views/ExtractedItemsReviewView.swift`, `Views/ReceiptPreviewSheet.swift`, `Views/ReceiptReviewView.swift` | mixed state in views plus service-driven calls |

### Component Library

Reusable SwiftUI components are organized in:

- `Views/Components/Avatars/`
- `Views/Components/Buttons/`
- `Views/Components/Cards/`
- `Views/Components/FormFields/`
- `Views/Components/Media/`
- `Views/Components/Receipt/`
- `DesignSystem/` for color/style primitives

### Tests

- SwiftPM tests: `ios/ClearSplit/Tests/ClearSplitTests/`
- Xcode test targets: `ios/ClearSplit/ClearSplit/ClearSplitTests/` and `.../ClearSplitUITests/`

Current automated iOS test depth is light compared to backend coverage.

### Repository Realities To Know

- The active production UI code is in `Sources/ClearSplit`.
- `ios/ClearSplit/ClearSplit/ClearSplit/ContentView.swift` is still template-style and not the primary app experience.
- Placeholder directories (`Core/`, `Features/`, `Models/`, `Networking/` at `ios/ClearSplit/`) remain from earlier structure plans.
