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

## Team Setup (Intel + Apple Silicon)
- Architectures: keep "Standard Architectures" for all targets; **do not** exclude `arm64`.  
- Build Active Architecture Only: Debug = YES, Release = NO.  
- Deployment Target: iOS 16.0. (Package.swift sets `.iOS(.v16)`.)
- Simulator pick: e.g. `iPhone 15`. CLI build:  
  `xcodebuild -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15' build`
- DerivedData cleanup: `xcodebuild -scheme ClearSplit clean` or delete `~/Library/Developer/Xcode/DerivedData`.
- BASE_URL: set `API_BASE_URL` in Info.plist or scheme xcconfig. Defaults to `http://localhost:8000` (use your Mac’s LAN IP for device).
- No Rosetta/arch hacks. If you see arch errors, ensure pods/SPM targets use iOS 16.0 and Standard Architectures.
