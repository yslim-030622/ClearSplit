# Build Fix Guide

## Fixes Applied

### 1. Fixed async task warnings
**Issue:** `expensesTask` and `balancesTask` inferred to have type '()'
**Fix:** Changed from storing results to fire-and-forget pattern:
```swift
// Before:
async let expensesTask = loadExpenses(groupId: groupId)
try await expensesTask

// After:
async let _ = loadExpenses(groupId: groupId)
```

### 2. Fixed Decimal multiplication errors
**Issue:** Binary operator '*' cannot be applied to Decimal and numeric literals
**Fix:** Explicitly cast to NSDecimalNumber:
```swift
// Before:
let totalCents = Int((price * 100).rounded())

// After:
let totalCents = Int(truncating: (price * Decimal(100)) as NSDecimalNumber)
```

### 3. Fixed token refresh encoding
**Issue:** refresh_token not being sent in snake_case
**Fix:** Added proper encoding strategy to local encoder

## Clean Build Steps

1. **Close Xcode completely** (Command + Q)

2. **Clean derived data:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

3. **Clean the project build folder:**
```bash
cd /Users/yslim0622/ClearSplit/ios/ClearSplit
rm -rf build/
```

4. **Reopen Xcode**

5. **Clean Build Folder** (Shift + Command + Option + K)

6. **Build** (Command + B)

7. **Run** (Command + R)

## If Build Still Fails

Check for these specific issues in Xcode's error panel:

1. **"sheet" error** - Make sure you're in the correct ClearSplitApp.swift file (not the modular version)
2. **Type-check timeout** - Usually resolved by clean build
3. **Decoder closure error** - Already fixed in the code

## Verify Server is Running

```bash
# Check if server is running
lsof -ti:8000

# If not running, start it:
cd /Users/yslim0622/ClearSplit/backend
source venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Expected Result

After successful build and run:
- App launches
- Can sign up / log in
- Can create groups
- Can view Shopping Sessions
- Can create sessions and add items

