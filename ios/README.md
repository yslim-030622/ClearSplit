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

## CI/CD Architecture

Assumptions:
- Scheme: `ClearSplit`
- Deployment target: iOS 16.0
- Build system: Xcode project + local Swift package (`ClearSplitCore`)
- CI platform: GitHub Actions with Fastlane lanes and shell scripts in `ios/ClearSplit/scripts`

Pipeline stages:
- PR (`.github/workflows/ios-pr-checks.yml`): lint + simulator build + unit tests.
- Main (`.github/workflows/ios-main-checks.yml`): lint + simulator build + unit tests + UI smoke + unsigned archive.
- Optional TestFlight (`workflow_dispatch` with `deploy_testflight=true`): runs only when release credentials are present.

## Local Workflow

Setup:
```bash
cd ios/ClearSplit
bundle install
```

Fastlane lanes:
```bash
cd ios/ClearSplit
bundle exec fastlane ios lint
bundle exec fastlane ios build
bundle exec fastlane ios test_unit
bundle exec fastlane ios test_ui
bundle exec fastlane ios test_all
bundle exec fastlane ios archive
bundle exec fastlane ios ci_pr
bundle exec fastlane ios ci_main
```

Direct script equivalents:
```bash
cd ios/ClearSplit
./scripts/ios_lint.sh
./scripts/ios_build.sh
./scripts/ios_test.sh unit
./scripts/ios_test.sh ui
./scripts/ios_test.sh all
./scripts/ios_archive.sh
```

Notes:
- Scripts auto-select an available iPhone simulator. You can override with `IOS_DESTINATION` or `IOS_SIMULATOR_NAME`.
- CI artifacts and logs are written under `ios/ClearSplit/.build/ci-results` and `ios/ClearSplit/.build/logs`.

## Branching and PR Rules

- Create feature branches from `main` and keep PR scope small.
- Required iOS PR checks: lint + build + unit tests (`iOS PR Checks` workflow).
- Do not merge if any iOS required check is failing.
- Main branch should stay releasable: full iOS validation (including UI smoke + archive) must remain green.
- Keep TestFlight upload manual and explicit via workflow dispatch.

## Test Strategy

- Unit tests (`ClearSplitTests`) focus on deterministic model/utility/network decoding behavior.
- UI smoke tests (`ClearSplitUITests`) validate critical launch/login/signup navigation with explicit waits and test-only launch arguments.
- Test stabilization hooks:
- `UITEST_MODE` forces a logged-out deterministic state in app startup.
- `UITEST_DISABLE_ANIMATIONS` disables UIKit animations in test runs.
- Retry policy for UI tests is enabled in CI (`-retry-tests-on-failure -test-iterations 2`).

## TestFlight (Optional)

The `ios testflight` lane is implemented but not run automatically. Configure CI secrets first:
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_CONTENT` (base64 API key content)
- `IOS_APP_IDENTIFIER`
- `APP_STORE_CONNECT_TEAM_ID` (optional if single team)
- `APPLE_DEVELOPER_TEAM_ID` (optional if single team)

Do not commit credentials or key files. Use GitHub Actions encrypted secrets only.

## Troubleshooting CI Failures

`Unable to find destination`:
- Re-run with simulator override, for example `IOS_SIMULATOR_NAME='iPhone 17' ./scripts/ios_test.sh unit`.
- Verify available destinations: `xcodebuild -project ClearSplit/ClearSplit.xcodeproj -scheme ClearSplit -showdestinations`.

`SwiftLint not found`:
- Install once: `brew install swiftlint`.

`Bundler/Fastlane errors`:
- Refresh gems: `bundle install`.
- Check lane list: `bundle exec fastlane lanes`.

`xcodebuild package/cache permission errors` in restricted environments:
- Use CI runners or run commands with permissions that allow Xcode simulator/cache access.

`UI tests flaky locally`:
- Close Simulator and rerun.
- Run only UI smoke suite: `./scripts/ios_test.sh ui`.
- Keep `UITEST_MODE` launch argument enabled in tests.

## Team Setup (Intel + Apple Silicon)
- Architectures: keep "Standard Architectures" for all targets; do not exclude `arm64`.
- Build Active Architecture Only: Debug = YES, Release = NO.
- Deployment Target: iOS 16.0 (`Package.swift` sets `.iOS(.v16)`).
- DerivedData cleanup: `xcodebuild -scheme ClearSplit clean` or delete `~/Library/Developer/Xcode/DerivedData`.
- BASE_URL resolution order: Run Scheme environment variable `API_BASE_URL` -> Info.plist `API_BASE_URL` -> default `http://127.0.0.1:8000`.
- For simulator traffic to deployed backend, set Run Scheme environment variable:
  `API_BASE_URL=https://clearsplit-backend-staging.livelypebble-460e405a.eastus.azurecontainerapps.io`.
- Shared scheme currently enables that staging `API_BASE_URL` by default. Remove/disable it in Scheme -> Run -> Arguments to return simulator traffic to local backend.
- Debug build also defines Info.plist `API_BASE_URL` as the staging URL for fallback when Scheme env vars are not applied.
