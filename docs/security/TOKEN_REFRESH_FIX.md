# Token Refresh Fix

## Problem
The iOS app was failing to refresh tokens with a 422 error:
```
"Field required","loc":["body","refresh_token"]
"input":{"refreshToken":"eyJ..."}
```

The backend expected `refresh_token` (snake_case) but received `refreshToken` (camelCase).

## Root Cause
The `refreshTokensDirectly()` method in `AppState` was creating its own `JSONEncoder` and `JSONDecoder` without configuring the key encoding/decoding strategies:

```swift
let decoder = JSONDecoder()  // Missing .convertFromSnakeCase
let encoder = JSONEncoder()  // Missing .convertToSnakeCase
```

This method is used by the `APIClient` when it encounters a 401 response and needs to refresh the token.

## Solution
Added the proper key encoding/decoding strategies to the locally created encoder and decoder:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase  // ✅ Added
let encoder = JSONEncoder()
encoder.keyEncodingStrategy = .convertToSnakeCase    // ✅ Added
```

## Why This Happened
- The `APIClient` class properly configures its encoder with `.convertToSnakeCase`
- However, `refreshTokensDirectly()` creates a direct HTTP request using its own encoder
- This was done to avoid circular dependencies during token refresh
- But the locally created encoder was missing the key strategy configuration

## Test
Rebuild and run the app. The token refresh should now work correctly:
1. Sign up / Login successfully
2. Wait for token to expire (or simulate 401)
3. App should automatically refresh token with correct field names
4. All subsequent API calls should work

## Files Changed
- `ios/ClearSplit/ClearSplit/ClearSplit/ClearSplitApp.swift`
  - Line ~560: Added `decoder.keyDecodingStrategy = .convertFromSnakeCase`
  - Line ~562: Added `encoder.keyEncodingStrategy = .convertToSnakeCase`

