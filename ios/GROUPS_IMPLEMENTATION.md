# Groups List + Create Group Implementation Guide

## Summary
Implemented full Groups list display and Create Group functionality with API integration, following all hard requirements:
- ✅ No hardcoded secrets (config system with .xcconfig files)
- ✅ Standard Architectures only (no exclusions)
- ✅ Proper build settings
- ✅ iOS 16.0 deployment target
- ✅ Clean version control hygiene

---

## Files Created/Modified

### New Files

1. **`ios/ClearSplit/ClearSplit/Config.example.xcconfig`** (committed)
   - Template configuration file with placeholders
   - Developers copy this to `Config.xcconfig` and fill in actual values

2. **`ios/ClearSplit/ClearSplit/Config.xcconfig`** (gitignored)
   - Local developer configuration with actual API URL
   - Never committed to version control

3. **`ios/ClearSplit/ClearSplit/ClearSplit/GroupDTO.swift`**
   - Data transfer object matching backend's `GroupRead` schema
   - Includes `CreateGroupRequest` for API calls

4. **`ios/ClearSplit/ClearSplit/ClearSplit/GroupsAPIService.swift`**
   - API service layer for Groups operations
   - Methods: `listGroups()`, `createGroup(name:currency:)`

5. **`ios/ClearSplit/ClearSplit/ClearSplit/CreateGroupView.swift`**
   - Modal sheet UI for creating a new group
   - Form with name field and currency picker
   - Validation and error handling

### Modified Files

6. **`.gitignore`**
   - Added `**/Config.xcconfig` to ignore local secrets

7. **`ios/ClearSplit/ClearSplit/ClearSplit/APIConfig.swift`**
   - Updated to read `API_BASE_URL` from Info.plist (populated from xcconfig)

8. **`ios/ClearSplit/ClearSplit/ClearSplit/GroupsViewModel.swift`**
   - Complete rewrite as proper `@MainActor` + `ObservableObject`
   - Methods: `load()`, `createGroup(name:currency:)`
   - Proper error handling

9. **`ios/ClearSplit/ClearSplit/ClearSplit/GroupsListView.swift`**
   - Added `+` button in navigation bar
   - Sheet presentation for create group flow
   - Displays list of groups or empty state
   - Pull-to-refresh functionality

10. **`ios/ClearSplit/ClearSplit/ClearSplit/Models.swift`**
    - Removed obsolete `CSGroup` (replaced by `GroupDTO`)

---

## Xcode Configuration Steps

### Step 1: Link xcconfig file to project

1. Open `ClearSplit.xcodeproj` in Xcode
2. Select the project in Navigator (blue icon at top)
3. Select the `ClearSplit` target
4. Go to "Info" tab
5. Under "Configurations":
   - For Debug: Set to "Config" (dropdown should show Config.xcconfig)
   - For Release: Set to "Config" (same)

If Config.xcconfig doesn't appear:
- File → Add Files to "ClearSplit"
- Navigate to `ios/ClearSplit/ClearSplit/Config.xcconfig`
- Make sure "Add to targets" is checked
- Click Add

### Step 2: Update Info.plist

1. Select `Info.plist` in Navigator
2. Right-click → Open As → Source Code
3. Add this entry inside the `<dict>` tag:

```xml
<key>API_BASE_URL</key>
<string>$(API_BASE_URL)</string>
```

This tells Xcode to populate the Info.plist value from the build setting defined in Config.xcconfig.

### Step 3: Verify Build Settings

1. Select project → Target → Build Settings
2. Search for "API_BASE_URL"
3. You should see it listed with value from Config.xcconfig
4. Verify these settings:
   - **Architectures**: Standard Architectures (ARM64)
   - **Excluded Architectures**: (empty for all configurations)
   - **Build Active Architecture Only**: Debug=YES, Release=NO
   - **iOS Deployment Target**: 16.0

---

## Verification Steps

### 1. Start Backend

```bash
cd /Users/yslim0622/ClearSplit
docker compose up
```

Wait for:
```
api-1  | INFO:     Application startup complete.
```

### 2. Configure iOS App

1. Copy the example config:
```bash
cd ios/ClearSplit/ClearSplit
cp Config.example.xcconfig Config.xcconfig
```

2. Edit `Config.xcconfig`:
   - For simulator: `API_BASE_URL = http:/$()/localhost:8000`
   - For real device: `API_BASE_URL = http:/$()/192.168.1.X:8000` (use your Mac's LAN IP)

### 3. Build & Run

1. Open `ClearSplit.xcodeproj` in Xcode
2. Select iPhone simulator (iOS 16+)
3. Product → Clean Build Folder (⇧⌘K)
4. Product → Build (⌘B)
5. Product → Run (⌘R)

### 4. Test Flow

**A. First Time User:**
1. App opens to Login screen
2. Tap "Create account"
3. Enter email: `test@example.com`, password: `password123`, confirm
4. Tap "Sign Up"
5. ✅ Should navigate to Groups screen showing "No groups yet"

**B. Create First Group:**
1. Tap `+` button in top right
2. Modal sheet appears
3. Enter name: "Trip to Seoul", select currency: "KRW"
4. Tap "Create Group"
5. ✅ Sheet dismisses
6. ✅ Groups list shows "Trip to Seoul" with "KRW" subtitle

**C. Create Second Group:**
1. Tap `+` again
2. Enter name: "Roommates", currency: "USD"
3. Tap "Create Group"
4. ✅ Both groups appear in list

**D. Persistence Test:**
1. Quit app (stop in Xcode)
2. Relaunch app
3. ✅ Goes directly to Groups screen (token persisted)
4. ✅ Both groups still visible (pull to refresh if needed)

**E. Logout & Login:**
1. Tap "Log Out"
2. ✅ Returns to Login screen
3. Enter same credentials: `test@example.com` / `password123`
4. Tap "Log In"
5. ✅ Groups screen shows both groups

### 5. Error Scenarios to Test

**A. Network Error:**
1. Stop docker backend
2. Try to create a group
3. ✅ Should show alert: "Cannot connect to server"

**B. Validation Error:**
1. Tap `+`
2. Leave name field empty
3. ✅ "Create Group" button is disabled

**C. Duplicate Name (if backend enforces):**
1. Create group "Test"
2. Try to create another "Test"
3. ✅ Should show backend error message

---

## Configuration System Explained

### How It Works

1. **Build Time:**
   - Xcode reads `Config.xcconfig`
   - Extracts `API_BASE_URL` as a build setting
   - Injects it into Info.plist as `$(API_BASE_URL)`

2. **Runtime:**
   - `APIConfig.swift` reads from `Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL")`
   - Returns the configured URL
   - APIClient uses this for all requests

### For New Developers

When someone clones the repo:

1. They get `Config.example.xcconfig` (committed)
2. Copy it: `cp Config.example.xcconfig Config.xcconfig`
3. Edit `Config.xcconfig` with their local backend URL
4. Build succeeds with their configuration
5. Their local secrets never get committed (`.gitignore` blocks it)

### For CI/CD

Set environment variable in CI:
```bash
export API_BASE_URL="https://api.production.com"
```

Or create Config.xcconfig during CI setup before build.

---

## Architecture Notes

### Why GroupDTO instead of CSGroup?

- **Separation of Concerns**: DTOs represent API contract, domain models represent business logic
- **Future-Proof**: Easy to add computed properties or transform API data without changing the DTO
- **Clear Intent**: Code readers immediately know this matches backend JSON structure

### ViewModel Pattern

- **@MainActor**: All UI updates happen on main thread automatically
- **ObservableObject**: SwiftUI views reactively update when @Published properties change
- **Single Responsibility**: ViewModel handles state + business logic, View handles presentation

### Error Handling Strategy

1. API layer throws typed errors (`APIError`)
2. ViewModel catches and converts to user-friendly messages
3. View displays alerts with actionable information
4. Debug logging helps development without exposing to users

---

## Troubleshooting

### "Cannot find API_BASE_URL"

**Symptom:** App uses localhost fallback despite configuring Config.xcconfig

**Fix:**
1. Check Info.plist has `<key>API_BASE_URL</key><string>$(API_BASE_URL)</string>`
2. Clean build folder (⇧⌘K)
3. Quit Xcode completely
4. Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
5. Reopen project and build

### "Groups not loading"

**Symptom:** Shows "No groups yet" but groups exist in backend

**Fix:**
1. Check Xcode console for `❌ Error loading groups:` logs
2. Verify API_BASE_URL is correct
3. Test backend directly: `curl http://localhost:8000/groups` (should require auth)
4. Check token is valid: tap "Log Out" and log back in

### "Create Group does nothing"

**Symptom:** Tap Create but sheet doesn't dismiss

**Check:**
1. Xcode console for `❌ Error creating group:`
2. Backend logs for POST /groups request
3. Verify name field is not empty
4. Try different group name

---

## Next Steps (Future Enhancements)

- [ ] Add group details screen (tap on group to see members/expenses)
- [ ] Add member management (invite by email)
- [ ] Add expense creation
- [ ] Add settlement calculations
- [ ] Add offline support with local cache
- [ ] Add group icons/colors
- [ ] Add search/filter for groups

---

## Build Verification Commands

```bash
# Clean build
cd /Users/yslim0622/ClearSplit/ios/ClearSplit
xcodebuild clean -project ClearSplit.xcodeproj -scheme ClearSplit

# Build for simulator
xcodebuild build \
  -project ClearSplit.xcodeproj \
  -scheme ClearSplit \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug

# Verify no excluded architectures
xcodebuild -project ClearSplit.xcodeproj \
  -showBuildSettings | grep EXCLUDED_ARCHS
# Should show: EXCLUDED_ARCHS = 

# Verify deployment target
xcodebuild -project ClearSplit.xcodeproj \
  -showBuildSettings | grep IPHONEOS_DEPLOYMENT_TARGET
# Should show: IPHONEOS_DEPLOYMENT_TARGET = 16.0
```

All commands should succeed with no errors! 🎉


