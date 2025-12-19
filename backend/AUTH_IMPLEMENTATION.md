# Phase 1 Authentication Implementation

## Overview

Phase 1 authentication system with email/password signup, login, JWT tokens, and user management.

## Files Created/Modified

### Created Files:
1. `app/auth/password.py` - Password hashing utilities (bcrypt)
2. `app/auth/jwt.py` - JWT token generation and validation
3. `app/auth/dependencies.py` - FastAPI dependencies for authentication
4. `app/schemas/auth.py` - Authentication request/response schemas
5. `app/api/auth.py` - Authentication API routes
6. `app/tests/test_auth.py` - Authentication tests

### Modified Files:
1. `requirements.txt` - Added bcrypt and python-jose
2. `app/core/config.py` - Added JWT configuration settings
3. `app/main.py` - Added auth router
4. `app/schemas/__init__.py` - Added auth schema exports
5. `app/tests/conftest.py` - Added HTTP client fixture

## Features

### Password Security
- **bcrypt** hashing with automatic salt generation
- Secure password verification

### JWT Tokens
- **Access Token**: Short-lived (15 minutes default)
- **Refresh Token**: Long-lived (30 days default)
- Token type validation (access vs refresh)
- User ID and email in token payload

### API Endpoints

#### POST /auth/signup
Create a new user account.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response:** 201 Created
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

#### POST /auth/login
Authenticate existing user.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response:** 200 OK
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "user": {
    "id": "uuid",
    "email": "user@example.com"
  }
}
```

#### POST /auth/refresh
Refresh access token using refresh token.

**Request:**
```json
{
  "refresh_token": "eyJ..."
}
```

**Response:** 200 OK
```json
{
  "access_token": "eyJ...",
  "token_type": "bearer"
}
```

#### GET /auth/me
Get current authenticated user information.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response:** 200 OK
```json
{
  "id": "uuid",
  "email": "user@example.com"
}
```

## Configuration

Add to `.env`:
```bash
JWT_SECRET=your-secret-key-change-in-production
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
```

## Testing

Run authentication tests:
```bash
cd backend
pytest app/tests/test_auth.py -v
```

Test coverage:
- ✅ Successful signup
- ✅ Duplicate email signup (error)
- ✅ Successful login
- ✅ Invalid email login (error)
- ✅ Invalid password login (error)
- ✅ Successful token refresh
- ✅ Invalid refresh token (error)
- ✅ Get current user with valid token
- ✅ Get current user with invalid token (error)
- ✅ Get current user without token (error)
- ✅ Expired token handling

## Local Setup Instructions

1. **Install dependencies:**
   ```bash
   cd backend
   pip install -r requirements.txt
   ```

2. **Set environment variables:**
   ```bash
   # Copy .env.example to .env and set:
   JWT_SECRET=your-secret-key-here
   DATABASE_URL=postgresql+asyncpg://clearsplit:clearsplit@localhost:5432/clearsplit
   ```

3. **Start database:**
   ```bash
   docker-compose up -d db
   ```

4. **Run migrations:**
   ```bash
   alembic upgrade head
   ```

5. **Start server:**
   ```bash
   make run
   # or
   uvicorn app.main:app --reload
   ```

6. **Test endpoints:**
   See curl commands below.

## Sample curl Commands

### 1. Signup
```bash
curl -X POST http://localhost:8000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### 2. Login
```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### 3. Refresh Token
```bash
# Replace <refresh_token> with actual refresh token from login/signup
curl -X POST http://localhost:8000/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refresh_token": "<refresh_token>"
  }'
```

### 4. Get Current User
```bash
# Replace <access_token> with actual access token from login/signup
curl -X GET http://localhost:8000/auth/me \
  -H "Authorization: Bearer <access_token>"
```

### 5. Test Invalid Password
```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "wrongpassword"
  }'
```

### 6. Test Expired Token
```bash
# Use an expired token (wait 15+ minutes after getting token)
curl -X GET http://localhost:8000/auth/me \
  -H "Authorization: Bearer <expired_access_token>"
```

## Security Notes

1. **Password Requirements**: Minimum 8 characters (enforced in schema)
2. **Token Expiration**: Access tokens expire in 15 minutes, refresh tokens in 30 days
3. **Password Hashing**: bcrypt with automatic salt generation
4. **JWT Secret**: Must be kept secure and not committed to version control
5. **HTTPS**: Use HTTPS in production to protect tokens in transit

## Next Steps

- [ ] Add rate limiting for auth endpoints
- [ ] Add email verification
- [ ] Add password reset flow
- [ ] Add token blacklisting for logout
- [ ] Add refresh token rotation

