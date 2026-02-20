# iOS Reference

## App Structure

The iOS client is a native SwiftUI application following MVVM architecture with zero external dependencies.

**87 Swift source files** organized by feature:

```
ios/ClearSplit/Sources/ClearSplit/
├── ClearSplitApp.swift           # App entry point
├── RootView.swift                # Auth gating (logged in → MainTabView, logged out → LoginView)
├── Config/
│   └── APIConfig.swift           # Base URL resolution
├── State/
│   └── AppState.swift            # Central state coordinator (438 lines)
├── Models/                       # Codable data models
│   ├── AuthModels.swift
│   ├── GroupModels.swift
│   ├── ExpenseModels.swift
│   ├── ShoppingModels.swift
│   ├── BalanceSettlementModels.swift
│   ├── SettlementModels.swift
│   └── FriendModels.swift
├── Networking/                   # API communication
│   ├── APIClient.swift           # Core HTTP client (390 lines)
│   ├── AuthService.swift
│   ├── GroupsService.swift
│   ├── ShoppingService.swift
│   ├── SettlementService.swift
│   ├── FriendsService.swift
│   └── HealthClient.swift
├── ViewModels/                   # Screen-level orchestration
│   ├── LoginViewModel.swift
│   ├── SignUpViewModel.swift
│   ├── GroupsViewModel.swift
│   ├── FriendsViewModel.swift
│   ├── ShoppingSessionDetailViewModel.swift
│   ├── CreateShoppingSessionViewModel.swift
│   └── AddItemViewModel.swift
├── Views/                        # 44 view files
│   ├── MainTabView.swift         # Tab navigation (Groups/Friends/Profile)
│   ├── LoginView.swift
│   ├── SignUpView.swift
│   ├── GroupsListView.swift
│   ├── GroupDetailView.swift
│   ├── ShoppingSessionsListView.swift
│   ├── ShoppingSessionDetailView.swift
│   ├── BalancesSettlementView.swift
│   ├── ReceiptUploadView.swift
│   ├── ReceiptReviewView.swift
│   ├── ExtractedItemsReviewView.swift
│   ├── FriendsTabView.swift
│   ├── ProfileTabView.swift
│   ├── CreateGroupView.swift
│   ├── CreateShoppingSessionView.swift
│   ├── AddItemSheet.swift
│   ├── EditItemSheet.swift
│   └── Components/              # 26 reusable UI components
│       ├── TotalAmountHeroCard.swift
│       ├── ItemsDetailCard.swift
│       ├── ParticipantsDetailCard.swift
│       ├── ReceiptsDetailCard.swift
│       ├── ParticipantAvatarView.swift
│       ├── ParticipantBadge.swift
│       ├── ParticipantPill.swift
│       ├── ReceiptThumbnailView.swift
│       ├── ReceiptUploadEmptyState.swift
│       ├── ReceiptUploadPreviewState.swift
│       ├── ReceiptUploadTips.swift
│       ├── ExtractedItemsList.swift
│       ├── ExtractedItemsEmptyState.swift
│       ├── ExtractedItemsErrorState.swift
│       ├── AddItemFixedButton.swift
│       ├── AddItemNameField.swift
│       ├── AddItemPriceQuantitySection.swift
│       ├── AddItemParticipantsSection.swift
│       ├── FlowLayout.swift
│       ├── TabLayoutMetrics.swift
│       └── ViewStateComponents.swift
├── DesignSystem/
│   ├── DesignSystem.swift        # Spacing, radius, elevation, typography tokens
│   ├── Colors.swift              # Semantic color palette
│   └── ButtonStyles.swift        # Reusable button styles
├── Storage/
│   └── KeychainService.swift     # Secure token persistence
├── Extensions/
│   └── ColorExtension.swift      # Hex color support
├── Utilities/
│   └── Formatting.swift          # Currency and date formatting
└── ViewModifiers/
    └── (elevation modifiers)
```

## AppState Responsibilities

`AppState` (`@MainActor ObservableObject`) is the central coordinator for:

- Session bootstrap and auth lifecycle
- Loading groups, members, expenses, balances, payments
- Shopping sessions, items, sharers, receipts, OCR extraction
- Mutating operations that keep local screen state in sync

### Published State

```swift
@Published var user: User?
@Published var isLoading = false
@Published var authError: String?

// Groups & Expenses
@Published var groups: [Group] = []
@Published var expensesByGroupId: [UUID: [Expense]] = [:]
@Published var membershipsByGroupId: [UUID: [Membership]] = [:]

// Balances & Settlements
@Published var groupBalancesByGroupId: [UUID: GroupBalances] = [:]
@Published var settlementPaymentsByGroupId: [UUID: [SettlementPayment]] = [:]

// Shopping Sessions
@Published var shoppingSessionsByGroupId: [UUID: [ShoppingSession]] = [:]
@Published var isLoadingShopping = false
```

### Bootstrap Sequence

1. Check Keychain for stored tokens
2. Call `/auth/me` to verify session
3. Load groups on success
4. If `/auth/me` fails, clear tokens and present login

### Key Methods

- `bootstrap()` — initial session check
- `login()`, `signup()`, `logout()` — auth flow
- `loadGroups()`, `createGroup()`, `deleteGroup()` — group management
- `loadExpenses()`, `createExpense()` — expense tracking
- `loadBalances()` — settlement calculations
- `loadShoppingSessions()`, `createShoppingSession()` — shopping
- `uploadReceipt()`, `extractReceiptItems()` — receipt OCR
- `createSettlementPayment()`, `confirmSettlementPayment()` — payments

## Networking Layer

### APIConfig

- Default base URL: `http://127.0.0.1:8000`
- Override via Xcode scheme environment variable: `API_BASE_URL`
- Fallback: Info.plist key `API_BASE_URL`
- Real-device hint logic warns against loopback URLs on physical devices

### APIClient Behavior

- Injects Bearer token for authenticated requests
- On `401`, refreshes tokens once and retries the original request
- Refresh flow coordinated by `AuthCoordinator` (Swift actor) to avoid duplicate simultaneous refresh calls
- Uses `convertFromSnakeCase` / `convertToSnakeCase` for JSON key conversion
- Date decoder accepts multiple ISO-8601 variants (with/without fractional seconds, microsecond precision)
- Supports both JSON requests and multipart upload (receipt images)
- Comprehensive debug logging for request/response cycles

### Request Pattern

```swift
struct APIRequest<T: Decodable> {
    let path: String
    var method: String = "GET"
    var body: Encodable?
    var requiresAuth: Bool = true
    var contentType: String?
}

// Usage
let expense: Expense = try await apiClient.request(
    APIRequest(
        path: "groups/\(groupId)/expenses",
        method: "POST",
        body: CreateExpenseRequest(...)
    )
)
```

### Service Layer (Protocol-Based)

Each service is protocol-defined for testability:

| Service | Protocol | Key Methods |
|---------|----------|-------------|
| `AuthService` | `AuthServicing` | login, signup, me, refresh |
| `GroupsService` | `GroupsServicing` | listGroups |
| `ShoppingService` | `ShoppingServicing` | sessions, receipts, items, sharers |
| `SettlementService` | `SettlementServicing` | balances, payments, confirm |
| `FriendsService` | `FriendsServicing` | friends, requests, accept/decline |

## Feature Coverage in UI

### Authentication

- Login screen uses username or email identifier
- Signup captures username, email, password, first/last name
- Error display with inline validation

### Groups and Members

- Groups tab lists current groups with create button
- Group detail loads members, balances, expenses, shopping sessions
- Member invite flow supports preview before add (owner only)

### Expenses and Balances

- Create equal-split expenses with payer selection
- Show live per-membership balances
- Generate and act on settlement suggestions
- Settlement payment history with confirmation workflow

### Shopping Sessions

- Create/list/open sessions with date and title
- Manage participants (payer only)
- Add/edit/delete items with flexible pricing
- Set per-item sharers with computed equal splits
- Upload and delete receipts (camera/photo library)
- Trigger and review OCR extracted items
- Finalize sessions and reflect settlement status

### Friends

- Send friend request by identifier or user ID
- Incoming/outgoing request lists
- Accept/decline/remove friendship

## Navigation Flow

```
RootView (auth gating)
├── Not bootstrapped → Loading spinner
├── Logged in → MainTabView
│   ├── Tab 1: Groups
│   │   ├── GroupsListView
│   │   │   └── GroupDetailView
│   │   │       ├── Members section
│   │   │       ├── Expenses section
│   │   │       ├── ShoppingSessionsListView
│   │   │       │   └── ShoppingSessionDetailView
│   │   │       │       ├── Participants
│   │   │       │       ├── Items (add/edit/delete/set sharers)
│   │   │       │       ├── Receipts (upload/view/OCR)
│   │   │       │       └── ExtractedItemsReviewView
│   │   │       └── BalancesSettlementView
│   │   └── CreateGroupView (sheet)
│   ├── Tab 2: Friends
│   │   └── FriendsTabView (friends list, requests)
│   └── Tab 3: Profile
│       └── ProfileTabView (user info, logout)
└── Logged out → LoginView ↔ SignUpView
```

## Design System

### Spacing Tokens
| Token | Value |
|-------|-------|
| xxs | 4pt |
| xs | 8pt |
| sm | 12pt |
| md | 16pt |
| lg | 20pt |
| xl | 24pt |
| xxl | 32pt |

### Corner Radius
| Token | Value |
|-------|-------|
| sm | 8pt |
| md | 12pt |
| lg | 16pt |
| xl | 20pt |
| pill | 999pt |

### Typography
- `hero` — large display text
- `title` — screen titles
- `sectionTitle` — section headers
- `body` / `bodyStrong` — content text
- `subheadline` — secondary content
- `footnote` / `caption` — small text

### Color Palette
- **Brand**: brandPrimary (blue600), brandPrimaryPressed, brandSubtle, brandSurface
- **Text**: textPrimary, textSecondary, textTertiary, textMuted, textOnBrand
- **Status**: success (green600), warning (amber600), danger (red600)
- **Surfaces**: dangerSurface, successSurface, warningSurface, infoSurface
- **UI**: borderMedium, pageBackground, cardBackground, overlayScrim

## Token Storage

- **Service**: KeychainService with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- **Account**: `com.clearsplit.auth` / `tokens`
- **Format**: JSON-encoded `AuthTokens` struct (accessToken, refreshToken, tokenType)
- **Operations**: load, save, clear
- **Cleared on**: logout

## Build, Test, Lint Scripts

From `ios/ClearSplit`:

```bash
# Direct scripts
./scripts/ios_build.sh            # Simulator build
./scripts/ios_test.sh unit        # Unit tests only
./scripts/ios_test.sh ui          # UI smoke tests
./scripts/ios_test.sh all         # Full test suite
./scripts/ios_lint.sh             # SwiftLint
./scripts/ios_archive.sh          # Unsigned release archive

# Via Fastlane
bundle exec fastlane ios lint
bundle exec fastlane ios build
bundle exec fastlane ios test_unit
bundle exec fastlane ios test_ui
bundle exec fastlane ios test_all
bundle exec fastlane ios archive
bundle exec fastlane ios ci_pr       # PR gate
bundle exec fastlane ios ci_main     # Main gate
```

Script behavior:
- Deterministic DerivedData and result bundle locations under `.build/`
- Simulator destination auto-resolution when not explicitly provided
- Override with `IOS_DESTINATION` or `IOS_SIMULATOR_NAME`
- Code signing disabled for CI-oriented build/test/archive scripts
- CI artifacts written to `ios/ClearSplit/.build/ci-results` and `.build/logs`

## Testing Strategy

### Unit Tests (`ClearSplitTests`)
- Focus: model decoding, network response parsing, state mutations
- Framework: XCTest (built-in)

### UI Smoke Tests (`ClearSplitUITests`)
- Validate critical launch/login/signup navigation
- Test arguments:
  - `UITEST_MODE` — forces logged-out deterministic state
  - `UITEST_DISABLE_ANIMATIONS` — disables UIKit animations for stability
- Retry policy in CI: 2 iterations (`-retry-tests-on-failure`)

## Local Runtime Notes

- Simulator can use default loopback URL (`http://127.0.0.1:8000`)
- Real devices require LAN-reachable backend URL in `API_BASE_URL`
- If you see immediate network failures on device, verify both backend bind host and local firewall settings
- Shared scheme may have staging `API_BASE_URL` configured by default — remove it in Scheme → Run → Arguments to use local backend

## Dependencies

**Zero external SPM dependencies.** Built entirely on:
- **Foundation** — base library
- **SwiftUI** — UI framework
- **Combine** — reactive patterns
- **Security** — Keychain access
- **UIKit** — limited use (haptic feedback only)

Build tool dependencies:
- Fastlane >= 2.222.0 (via Gemfile)
- SwiftLint (via Homebrew)
- Xcode 15+
