# ClearSplit iOS (SwiftUI)

Conventions:
- SwiftUI + MVVM; no business logic in Views.
- Async/await networking; Keychain for tokens.
- Models aligned with backend schemas; decoding using `JSONDecoder` with ISO-8601 UTC.

Layout:
- `ClearSplit/Core` — App entry, environment, DI.
- `ClearSplit/Models` — Shared domain models.
- `ClearSplit/Networking` — API client, auth refresh handling.
- `ClearSplit/Features` — Screens by feature (Auth, Groups, Expenses, Settlements).
- `ClearSplit/DesignSystem` — Reusable UI components/styles.
- `ClearSplit/Tests` — Unit/snapshot tests.
