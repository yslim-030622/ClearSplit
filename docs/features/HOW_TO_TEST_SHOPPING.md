# How to Test Shopping Sessions

This guide shows you how to test the new Shopping Sessions feature.

## What Changed

The app now focuses exclusively on **Shopping Sessions**. The old Expenses feature has been removed from the group detail view.

## Prerequisites

1. **Backend running**: `cd backend && source venv/bin/activate && uvicorn app.main:app --reload`
2. **iOS simulator running** with the app installed
3. **Test account**: `test2@test.com` (or any account)

## Quick Test Flow

1. **Login** with your test account
2. **Select a group** from your groups list
3. **Group detail view** now shows:
   - Group info (currency, created date, members)
   - Shopping Sessions section (one prominent button)
4. **Tap "View Shopping Sessions"** to access the feature
5. You should see a placeholder screen confirming the backend is ready

## Expected Behavior

### Current State
- Clean, focused group detail view
- No more Expenses or Balances sections
- Shopping Sessions is the main feature
- Placeholder screen shows your membership ID

### Coming Next
- Full shopping session list
- Create new sessions
- Upload receipts
- Add items with sharers
- View split calculations

## Backend Features Ready

The backend fully supports:
- Creating shopping sessions with title, date, payer
- Setting participants for a session
- Uploading receipt images (multipart)
- Creating items with price, quantity
- Assigning sharers to items
- Automatic equal split calculations

Test these endpoints using curl or Postman. Check backend logs for API calls.

## Troubleshooting

**Q: Button says "Shopping unavailable - please re-login"**
- Logout and login again to refresh your membership ID

**Q: Simulator shows old UI with Expenses**
- Clean build: Shift + Command + K in Xcode
- Quit simulator completely
- Rebuild and run

**Q: Backend not responding**
- Ensure backend server is running in terminal
- Check that virtual environment is activated
- Verify database is running: `docker-compose up -d`
