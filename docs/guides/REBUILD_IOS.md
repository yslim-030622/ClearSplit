# How to See the Shopping Changes in Simulator

The changes are in the code, but iOS might be using a cached build. Here's how to fix it:

## Steps in Xcode

1. Open `/Users/yslim0622/ClearSplit/ios/ClearSplit/ClearSplit.xcodeproj`

2. Clean the build:
   - Press `Shift + Command + K`
   - Or menu: Product → Clean Build Folder

3. Delete the app from simulator:
   - Run the simulator (Command + R)
   - Long-press the ClearSplit app icon
   - Tap the (x) to delete it
   - Stop the simulator

4. Build and run fresh:
   - Press `Command + R`

## What You Should See After Rebuild

**Groups List Screen:**
- Each group row should be tappable
- When you tap a group, it navigates to a new screen

**Group Detail Screen (NEW):**
- Shows group info at top
- Shows "Shopping Sessions" button with cart icon
- Shows "Expenses" button below it

**If you don't see this:**
- The app is still using the old build
- Try deleting derived data (see below)

## Delete Derived Data (if above doesn't work)

1. In Xcode: Settings → Locations
2. Click arrow next to "Derived Data"
3. Find and delete the ClearSplit folder
4. Close and reopen Xcode
5. Build again (Command + R)

## Verify Backend is Running

The backend needs to be running for the app to work:

```bash
curl http://localhost:8000/health
```

Should return: `{"status":"ok"}`

If not, restart it:

```bash
cd /Users/yslim0622/ClearSplit/backend
source venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## What Changed

**Before:** Groups List → (nothing clickable)

**After:** Groups List → (tap group) → Group Detail → (tap Shopping Sessions) → Shopping List

The navigation was added to `GroupsListView.swift` at line 23-24:
```swift
NavigationLink {
    GroupDetailView(appState: appState, group: group)
}
```

And `GroupDetailView.swift` shows the Shopping Sessions option at lines 15-26.

