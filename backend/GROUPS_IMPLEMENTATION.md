# Phase 2 Groups & Memberships Implementation

## Overview

Phase 2 groups and memberships endpoints with role-based access control. All endpoints require authentication.

## Files Created/Modified

### Created Files:
1. `app/services/group.py` - Group business logic and permission checks
2. `app/services/membership.py` - Membership business logic
3. `app/api/groups.py` - Groups and memberships API routes
4. `app/tests/test_groups.py` - Groups and memberships tests

### Modified Files:
1. `app/schemas/membership.py` - Added `AddMemberRequest` schema
2. `app/main.py` - Added groups router

## API Endpoints

### POST /groups
Create a new group. The creator is automatically added as the owner.

**Authentication:** Required

**Request:**
```json
{
  "name": "My Group",
  "currency": "USD"
}
```

**Response:** 201 Created
```json
{
  "id": "uuid",
  "name": "My Group",
  "currency": "USD",
  "version": 1,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

### GET /groups
List all groups where the current user is a member.

**Authentication:** Required

**Response:** 200 OK
```json
[
  {
    "id": "uuid",
    "name": "My Group",
    "currency": "USD",
    "version": 1,
    "created_at": "2024-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z"
  }
]
```

### GET /groups/{group_id}
Get a specific group by ID. User must be a member.

**Authentication:** Required

**Response:** 200 OK
```json
{
  "id": "uuid",
  "name": "My Group",
  "currency": "USD",
  "version": 1,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

**Errors:**
- 404: Group not found
- 403: User is not a member

### POST /groups/{group_id}/members
Add a member to a group. Only group owners can add members.

**Authentication:** Required

**Request (by user_id):**
```json
{
  "user_id": "uuid",
  "role": "member"
}
```

**Request (by email):**
```json
{
  "email": "user@example.com",
  "role": "member"
}
```

**Response:** 201 Created
```json
{
  "id": "uuid",
  "group_id": "uuid",
  "user_id": "uuid",
  "role": "member",
  "created_at": "2024-01-01T00:00:00Z"
}
```

**Errors:**
- 403: User is not an owner
- 404: Group not found or user not found
- 400: User is already a member or invalid request

### GET /groups/{group_id}/members
List all members of a group. User must be a member.

**Authentication:** Required

**Response:** 200 OK
```json
[
  {
    "id": "uuid",
    "group_id": "uuid",
    "user_id": "uuid",
    "role": "owner",
    "created_at": "2024-01-01T00:00:00Z"
  },
  {
    "id": "uuid",
    "group_id": "uuid",
    "user_id": "uuid",
    "role": "member",
    "created_at": "2024-01-01T00:00:00Z"
  }
]
```

**Errors:**
- 404: Group not found
- 403: User is not a member

## Permission Rules

### Group Access
- **Any authenticated user** can create a group (becomes owner)
- **Group members** can view their groups and group details
- **Non-members** cannot access group information (403 Forbidden)

### Member Management
- **Group owners** can add members to the group
- **Group members** (non-owners) cannot add members (403 Forbidden)
- **Group members** can view the member list
- **Non-members** cannot view the member list (403 Forbidden)

### Role Hierarchy
1. **owner**: Full control, can add members
2. **member**: Can view and participate
3. **viewer**: Read-only access (not yet implemented in endpoints)

## Transactions

All database operations use transactions:
- Group creation automatically creates owner membership in the same transaction
- Member addition is atomic (group existence and owner check in one transaction)

## Testing

Run tests:
```bash
cd backend
pytest app/tests/test_groups.py -v
```

Test coverage:
- ✅ Create group (creator becomes owner)
- ✅ List my groups
- ✅ Get group details
- ✅ Get group when not a member (403)
- ✅ Add member by user_id
- ✅ Add member by email
- ✅ Add member when not owner (403)
- ✅ Add member who already exists (400)
- ✅ List members
- ✅ List members when not a member (403)
- ✅ Add member with non-existent user (404)

## Sample curl Commands

### Prerequisites
First, get an access token by logging in:
```bash
# Login
TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password123"}' \
  | jq -r '.access_token')
```

### 1. Create Group
```bash
curl -X POST http://localhost:8000/groups \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Weekend Trip",
    "currency": "USD"
  }'
```

### 2. List My Groups
```bash
curl -X GET http://localhost:8000/groups \
  -H "Authorization: Bearer $TOKEN"
```

### 3. Get Group Details
```bash
# Replace <group_id> with actual group UUID
curl -X GET http://localhost:8000/groups/<group_id> \
  -H "Authorization: Bearer $TOKEN"
```

### 4. Add Member by Email
```bash
# Replace <group_id> with actual group UUID
curl -X POST http://localhost:8000/groups/<group_id>/members \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "friend@example.com",
    "role": "member"
  }'
```

### 5. Add Member by User ID
```bash
# Replace <group_id> and <user_id> with actual UUIDs
curl -X POST http://localhost:8000/groups/<group_id>/members \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "<user_id>",
    "role": "member"
  }'
```

### 6. List Group Members
```bash
# Replace <group_id> with actual group UUID
curl -X GET http://localhost:8000/groups/<group_id>/members \
  -H "Authorization: Bearer $TOKEN"
```

### 7. Test Permission (Non-Owner)
```bash
# Login as a different user (member, not owner)
MEMBER_TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "member@example.com", "password": "password123"}' \
  | jq -r '.access_token')

# Try to add member (should fail with 403)
curl -X POST http://localhost:8000/groups/<group_id>/members \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@example.com"
  }'
```

### 8. Test Access (Non-Member)
```bash
# Login as a user who is not a member
NON_MEMBER_TOKEN=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "outsider@example.com", "password": "password123"}' \
  | jq -r '.access_token')

# Try to get group (should fail with 403)
curl -X GET http://localhost:8000/groups/<group_id> \
  -H "Authorization: Bearer $NON_MEMBER_TOKEN"
```

## Error Responses

### 401 Unauthorized
```json
{
  "detail": "Invalid or expired token"
}
```

### 403 Forbidden
```json
{
  "detail": "You are not a member of this group"
}
```
or
```json
{
  "detail": "Only group owners can perform this action"
}
```

### 404 Not Found
```json
{
  "detail": "Group not found"
}
```
or
```json
{
  "detail": "User not found"
}
```

### 400 Bad Request
```json
{
  "detail": "User is already a member of this group"
}
```
or
```json
{
  "detail": "Either email or user_id must be provided"
}
```

## Implementation Notes

1. **Service Layer**: Business logic separated into service modules for reusability
2. **Permission Checks**: Centralized in service layer (`require_owner_role`, `require_membership`)
3. **Transactions**: Group creation and membership addition use database transactions
4. **Email vs User ID**: Flexible member addition by either email or user_id
5. **Role Default**: New members default to `member` role unless specified

