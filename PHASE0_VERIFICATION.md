# Phase 0 Verification Checklist

This document verifies that the Phase 0 skeleton is runnable and consistent.

## Prerequisites Check

```bash
# Docker Compose
docker-compose --version
# Expected: Docker Compose version v2.x.x

# Python
python3 --version
# Expected: Python 3.11.x or higher

# Xcode
xcodebuild -version
# Expected: Xcode 15.x or higher
```

## Task 1: Backend via Docker Compose

### Steps:
1. Ensure `.env` file exists (copy from `.env.example` if needed)
2. Start database:
   ```bash
   docker-compose up -d db
   ```
3. Wait for healthcheck (10-15 seconds), verify:
   ```bash
   docker-compose ps
   ```
   Expected: `db` service shows `healthy` status

4. Start backend API:
   ```bash
   docker-compose up api
   ```
   Or run locally:
   ```bash
   cd backend
   make install
   make run
   ```

5. Test health endpoint:
   ```bash
   curl http://localhost:8000/health
   ```
   Expected output: `{"status":"ok"}`

### Expected Output:
```json
{"status":"ok"}
```

## Task 2: Alembic Migrations

### Steps:
1. Ensure database is running (from Task 1)
2. Install dependencies:
   ```bash
   cd backend
   make install
   ```
3. Run migrations:
   ```bash
   alembic upgrade head
   ```

### Expected Output:
```
INFO  [alembic.runtime.migration] Running upgrade  -> 20241218_0001, initial schema
```

### Verify in Postgres:
```bash
docker-compose exec db psql -U clearsplit -d clearsplit -c "\dt"
```
Expected: Tables listed: `users`, `groups`, `memberships`, `expenses`, `expense_splits`, `settlement_batches`, `settlements`, `activity_log`, `idempotency_keys`

## Task 3: iOS Compilation

### Option A: Xcode GUI
```bash
open ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj
```
- Select scheme: `ClearSplit`
- Select destination: `iPhone 15 Simulator` (or any iOS 17+ simulator)
- Press `Cmd+B` to build
- Expected: Build succeeds without errors

### Option B: Command Line
```bash
cd ios/ClearSplit
xcodebuild -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Expected Output:
```
** BUILD SUCCEEDED **
```

## Task 4: .gitignore Verification

### Check project.pbxproj is NOT ignored:
```bash
git check-ignore -v ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj/project.pbxproj
```
Expected: No output (file is tracked)

### Check DerivedData/ is ignored:
```bash
git check-ignore -v DerivedData/
```
Expected: `.gitignore:15:DerivedData/ DerivedData/`

### Check xcuserdata/ is ignored:
```bash
git check-ignore -v ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj/xcuserdata/
```
Expected: `.gitignore:16:xcuserdata/ ios/ClearSplit/ClearSplit/ClearSplit.xcodeproj/xcuserdata/`

## Task 5: README Commands

The README.md has been updated with exact macOS commands. Verify:
- [ ] Commands are copy-pasteable
- [ ] Expected outputs are documented
- [ ] Prerequisites are listed
- [ ] Verification checklist is included

## Summary

All Phase 0 components should be:
- ✅ Runnable via documented commands
- ✅ Consistent across backend and iOS
- ✅ Properly version controlled (.gitignore correct)
- ✅ Documented with exact commands and expected outputs

