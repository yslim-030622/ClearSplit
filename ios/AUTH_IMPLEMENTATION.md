# ClearSplit iOS Auth Flow - Production Implementation

## Summary
Implemented production-grade authentication flow with centralized state management, secure token storage, and proper error handling.

## Architecture Changes

### 1. AuthManager (Single Source of Truth)
**File**: `ios/ClearSplit/ClearSplit/ClearSplit/AuthManager.swift`

Created centralized auth state manager:
- `@Published var isAuthenticated: Bool` - drives UI routing
- `@Published var isLoading: Bool` - shows loading states
- `@Published var errorMessage: String?` - displays user-friendly errors
- Methods: `bootstrap()`, `signUp()`, `logIn()`, `logOut()`

Key features:
- Bootstrap checks existing tokens at launch and validates with `/auth/me`
- Smart error handling: maps 400 duplicate email → "Email already registered"
- Debug-only LAN IP hint when localhost fails on physical devices
- Automatic navigation on successful auth (via `isAuthenticated` state)

### 2. Updated Views

#### ClearSplitApp.swift
- Creates `@StateObject authManager` and injects via `environmentObject`
- Debug logging: prints base URL at launch
- Reminder: simulator uses localhost, device needs LAN IP

#### RootView.swift
- Consumes `@EnvironmentObject authManager`
- Routes based on `authManager.isAuthenticated`:
  - `true` → `GroupsListView()`
  - `false` → `LoginView()`
- Calls `authManager.bootstrap()` on `.task`

#### LoginView.swift
- Removed local `LoginViewModel`, now uses `authManager` directly
- Fields: email, password (local `@State`)
- Button action: `await authManager.logIn(email:password:)`
- Disabled when loading or fields empty
- Alert shows `authManager.errorMessage`
- NavigationLink to `SignUpView()` (no bindings needed)

#### SignUpView.swift
- Uses `authManager` for sign-up
- Local validation: email not empty, password ≥8 chars, passwords match
- On success: auto-login handled by `AuthService.signup` → `authManager.isAuthenticated = true`
- Separate validation errors vs network errors

#### GroupsListView.swift
- Logout button now calls `authManager.logOut()`
- Removed `isAuthenticated` binding (AuthManager handles routing)

### 3. Keychain & Networking (No Changes Needed)

Existing implementations already production-ready:
- **KeychainService**: stores access/refresh tokens securely
- **AuthService**: signup auto-calls login, stores tokens
- **APIClient**: handles 401 refresh, converts snake_case

## Developer Experience

### Debug Logging
```swift
#if DEBUG
print("🚀 ClearSplit launching...")
print("📡 API Base URL: http://localhost:8000")
print("💡 Note: Simulator can use localhost. Physical devices must use Mac LAN IP.")
#endif
```

### Error Messages
- **401 login fail**: "Invalid email or password."
- **400 signup duplicate**: "Email already registered. Please log in instead."
- **Network error on localhost**: Shows LAN IP hint for physical devices
- **Other errors**: "Server error (500). Please try again."

## User Flow

### First Launch
1. App calls `authManager.bootstrap()`
2. No tokens → shows `LoginView`

### Sign Up Flow
1. User taps "Create account" → `SignUpView`
2. Enters email/password/confirm
3. Client validates (≥8 chars, match)
4. Calls `authManager.signUp()` → `POST /auth/signup`
5. On success: auto-login → stores tokens → `isAuthenticated = true`
6. RootView routes to `GroupsListView`

### Login Flow
1. User enters email/password
2. Taps "Log In" → `authManager.logIn()`
3. On success: stores tokens → `isAuthenticated = true`
4. Routes to `GroupsListView`

### Logout Flow
1. User taps "Log Out" in Groups screen
2. Calls `authManager.logOut()` → clears Keychain
3. `isAuthenticated = false` → routes back to `LoginView`

### Subsequent Launches
1. `bootstrap()` finds tokens → calls `/auth/me`
2. Valid → `isAuthenticated = true` → goes straight to Groups
3. Expired → clears tokens → shows Login

## Files Changed

### Added
- `ios/ClearSplit/ClearSplit/ClearSplit/AuthManager.swift`

### Modified
- `ios/ClearSplit/ClearSplit/ClearSplit/ClearSplitApp.swift`
- `ios/ClearSplit/ClearSplit/ClearSplit/RootView.swift`
- `ios/ClearSplit/ClearSplit/ClearSplit/LoginView.swift`
- `ios/ClearSplit/ClearSplit/ClearSplit/SignUpView.swift`
- `ios/ClearSplit/ClearSplit/ClearSplit/GroupsListView.swift`

### No Longer Needed (can be deleted)
- `LoginViewModel.swift`
- `SignUpViewModel.swift`
- `GroupsViewModel.swift` (if not used elsewhere)

## Build Settings (Unchanged)
- **Architectures**: Standard (no excluded archs)
- **Build Active Architecture Only**: Debug=YES, Release=NO
- **Deployment Target**: iOS 16.0
- **Base URL**: Configurable via Info.plist (`API_BASE_URL`)

## Testing Checklist

✅ **Signup with new email** → auto-login → Groups screen  
✅ **Signup with existing email** → alert "Email already registered"  
✅ **Login with valid credentials** → Groups screen  
✅ **Login with invalid password** → alert "Invalid email or password"  
✅ **Logout** → back to Login screen  
✅ **Relaunch app (with tokens)** → straight to Groups  
✅ **Relaunch app (no tokens)** → Login screen  
✅ **Network error** → alert with clear message  

## Next Steps (Optional)
1. Delete unused ViewModels if confirmed not needed elsewhere
2. Add biometric auth (Face ID/Touch ID) for returning users
3. Add "Forgot Password" flow
4. Add loading skeleton for Groups list


