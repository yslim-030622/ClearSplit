# iOS Shopping Sessions Integration - Complete

## What Was Implemented

### 1. Data Models
Added complete shopping data models to `ClearSplitApp.swift`:
- `ShoppingSession` - Main shopping session with total calculation
- `ShoppingSessionParticipant` - Participants in a session
- `ReceiptUpload` - Receipt image metadata
- `ShoppingItem` - Individual items with quantity and price
- `ShoppingItemSplit` - Split amounts per participant
- Request/Response models for API calls

### 2. API Integration
Added complete shopping API methods to `APIClient`:
- `listShoppingSessions(groupId:)` - Get all sessions for a group
- `createShoppingSession(groupId:, request:)` - Create new session
- `getShoppingSession(sessionId:)` - Get session details
- `setParticipants(sessionId:, membershipIds:)` - Set session participants
- `createShoppingItem(sessionId:, request:)` - Add item to session
- `setItemSharers(itemId:, membershipIds:)` - Set who shares an item

### 3. State Management
Extended `AppState` with shopping functionality:
- `shoppingSessionsByGroupId` - Cache of sessions per group
- `isLoadingShopping` - Loading state
- `loadShoppingSessions(groupId:)` - Load sessions from API
- `createShoppingSession(groupId:, title:, paidBy:)` - Create new session
- `refreshShoppingSession(sessionId:, groupId:)` - Refresh single session
- `setSessionParticipants()` - Update participants
- `createShoppingItem()` - Add new item
- `setItemSharers()` - Set item sharers

### 4. Complete UI Flow
Implemented 5 new views for full shopping functionality:

#### a. ShoppingSessionsListView
- Shows all shopping sessions for a group
- Empty state with helpful message
- Create button to start new session
- Displays session title, total, item count, date
- Pull to refresh support

#### b. CreateShoppingSessionSheet
- Simple form to create new shopping session
- Title input with validation
- Creates session with current user as payer

#### c. ShoppingSessionDetailView
- Shows session summary (total, participant count)
- Lists all participants with "You" indicator
- Lists all items with splits breakdown
- Shows each sharer's amount per item
- Add item button (disabled until participants are set)
- Edit participants button

#### d. SetParticipantsSheet
- Checkable list of all group members
- Shows member names and emails
- Pre-selects current participants when editing
- Validates at least one participant is selected

#### e. AddItemSheet
- Form for item details (name, quantity, price)
- Checkable list of session participants
- Real-time split amount preview per person
- Validates all required fields
- Creates item and sets sharers in one flow

### 5. Integration Points
- **GroupDetailView** - Updated to navigate to Shopping Sessions
- **APIClient** - All shopping endpoints connected
- **AppState** - Shopping state management integrated
- **formatCurrency** - Helper function for consistent money formatting

## How to Use

### 1. Run the App
Make sure the backend server is running:
```bash
cd /Users/yslim0622/ClearSplit/backend
source venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. Test the Flow
1. **Login** to the app (use test2@test.com or create account)
2. **Select a Group** from the groups list
3. **Tap "Shopping Sessions"** - you'll see the shopping list
4. **Create a Session**:
   - Tap the "+" button
   - Enter a title like "Costco Run 1/7"
   - Tap "Create"
5. **Set Participants**:
   - Tap the new session
   - Tap "Set Participants"
   - Select yourself and any other members
   - Tap "Save"
6. **Add Items**:
   - Tap the "+" button (now enabled)
   - Enter item name (e.g., "Milk")
   - Enter quantity (e.g., "2")
   - Enter price (e.g., "6.99")
   - Check who's sharing this item
   - Notice the split amount shown per person
   - Tap "Add"
7. **View Results**:
   - See the item with splits breakdown
   - See your share highlighted in green
   - See the total at the top

### 3. Features to Test
- ✅ Create multiple sessions
- ✅ Add multiple items per session
- ✅ Different sharers for different items
- ✅ Edit participants after creation
- ✅ View split breakdown per item
- ✅ Pull to refresh sessions list
- ✅ Navigate back and forth
- ✅ Empty states with helpful messages

## What's Different from the Modular Code

The shopping feature was integrated into the monolithic `ClearSplitApp.swift` file (not the modular `Sources/ClearSplit` directory) because that's the file Xcode is actually building. All shopping code is fully functional within this single file.

## Known UI Patterns

- **"You" vs UUID prefix** - Participants are shown as "You" for current user, or first 8 chars of UUID for others (until we add member name lookup)
- **Green vs Blue** - Current user shown in green, others in blue
- **Disabled states** - Add item button disabled until participants are set
- **Real-time preview** - Split amounts update as you check/uncheck sharers
- **Validation** - All forms validate input before enabling submit

## Next Steps (Optional Enhancements)

1. Show actual member names instead of UUID prefixes
2. Add receipt photo upload UI
3. Add date picker for shopping date
4. Add currency symbol based on group currency (not just $)
5. Add edit/delete for items
6. Add session summary with "who owes what"
7. Add search/filter for sessions list
8. Add sorting options (by date, by total, etc.)

## Backend Connection

All API endpoints are connected and tested:
- ✅ POST `/groups/{id}/shopping-sessions` - Create session
- ✅ GET `/groups/{id}/shopping-sessions` - List sessions
- ✅ GET `/shopping-sessions/{id}` - Get session details
- ✅ PUT `/shopping-sessions/{id}/participants` - Set participants
- ✅ POST `/shopping-sessions/{id}/items` - Create item
- ✅ PUT `/items/{id}/sharers` - Set item sharers

The iOS app now fully supports the Shopping Sessions feature end-to-end!

