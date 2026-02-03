# ClearSplit Documentation Index

This is a comprehensive index of all documentation files in the ClearSplit repository.

## 📋 Table of Contents

1. [Project Overview](#project-overview)
2. [Getting Started](#getting-started)
3. [Architecture & Design](#architecture--design)
4. [Backend Documentation](#backend-documentation)
5. [iOS Documentation](#ios-documentation)
6. [Feature Documentation](#feature-documentation)
7. [Testing & Verification](#testing--verification)
8. [Troubleshooting](#troubleshooting)
9. [Security](#security)
10. [Development Notes](#development-notes)

---

## Project Overview

- **[README.md](../README.md)** - Main project overview, structure, and setup instructions
- **[docs/INDEX.md](./INDEX.md)** - Original documentation index
- **[SESSION_SUMMARY.md](../SESSION_SUMMARY.md)** - Recent session context and changes
- **[WHAT_YOULL_SEE.md](../WHAT_YOULL_SEE.md)** - Expected app behavior walkthrough

---

## Getting Started

- **[README.md](../README.md)** - Complete setup guide for backend and iOS
- **[backend/README.md](../backend/README.md)** - Backend-specific setup and conventions
- **[ios/README.md](../ios/README.md)** - iOS-specific setup and conventions

---

## Architecture & Design

- **[docs/adr/0001-non-negotiables.md](./adr/0001-non-negotiables.md)** - Architecture Decision Record: Non-negotiables
- **[docs/db.md](./db.md)** - Database schema and design notes
- **[SHOPPING_MODEL.md](../SHOPPING_MODEL.md)** - Shopping sessions data model documentation

---

## Backend Documentation

### Implementation Guides

- **[backend/AUTH_IMPLEMENTATION.md](../backend/AUTH_IMPLEMENTATION.md)** - Authentication implementation details
- **[backend/EXPENSES_IMPLEMENTATION.md](../backend/EXPENSES_IMPLEMENTATION.md)** - Expenses feature implementation
- **[backend/GROUPS_IMPLEMENTATION.md](../backend/GROUPS_IMPLEMENTATION.md)** - Groups and membership implementation
- **[backend/MODELS_IMPLEMENTATION.md](../backend/MODELS_IMPLEMENTATION.md)** - Data models documentation
- **[backend/SCHEMAS_IMPLEMENTATION.md](../backend/SCHEMAS_IMPLEMENTATION.md)** - API schemas documentation

### Backend Overview

- **[backend/README.md](../backend/README.md)** - Backend architecture, conventions, and structure

---

## iOS Documentation

- **[ios/README.md](../ios/README.md)** - iOS app architecture, conventions, and setup
- **[IOS_INTEGRATION_COMPLETE.md](../IOS_INTEGRATION_COMPLETE.md)** - iOS integration completion summary
- **[REBUILD_IOS.md](../REBUILD_IOS.md)** - iOS rebuild instructions

---

## Feature Documentation

### Shopping Sessions

- **[SHOPPING_MODEL.md](../SHOPPING_MODEL.md)** - Shopping sessions data model
- **[SHOPPING_IMPLEMENTATION_SUMMARY.md](../SHOPPING_IMPLEMENTATION_SUMMARY.md)** - Shopping feature implementation summary
- **[HOW_TO_TEST_SHOPPING.md](../HOW_TO_TEST_SHOPPING.md)** - Shopping feature testing guide

### Implementation Summaries

- **[COMPLETE_FIX_SUMMARY.md](../COMPLETE_FIX_SUMMARY.md)** - Consolidated fix summary
- **[BACKEND_FIX_SUMMARY.md](../BACKEND_FIX_SUMMARY.md)** - Backend-specific fixes
- **[PARTICIPANT_FIX_STATUS.md](../PARTICIPANT_FIX_STATUS.md)** - Participant feature fix tracking

---

## Testing & Verification

- **[PHASE0_VERIFICATION.md](../PHASE0_VERIFICATION.md)** - Phase 0 verification checklist
- **[INTEGRATION_VERIFICATION.md](../INTEGRATION_VERIFICATION.md)** - Integration verification notes
- **[TESTING_SUMMARY.md](../TESTING_SUMMARY.md)** - Testing status and summary
- **[HOW_TO_TEST_SHOPPING.md](../HOW_TO_TEST_SHOPPING.md)** - Shopping feature testing guide

---

## Troubleshooting

- **[BUILD_FIX_GUIDE.md](../BUILD_FIX_GUIDE.md)** - Build fix steps and solutions
- **[BUILD_TROUBLESHOOTING.md](../BUILD_TROUBLESHOOTING.md)** - Common build issues and remedies
- **[REBUILD_IOS.md](../REBUILD_IOS.md)** - iOS rebuild steps

---

## Security

- **[SECURITY.md](../SECURITY.md)** - Security overview and practices
- **[SECURITY_PATCH.md](../SECURITY_PATCH.md)** - Security patches and changes
- **[SECURITY_HARDENING_SUMMARY.md](../SECURITY_HARDENING_SUMMARY.md)** - Security hardening notes
- **[TOKEN_REFRESH_FIX.md](../TOKEN_REFRESH_FIX.md)** - Token refresh implementation fixes

---

## Development Notes

- **[SESSION_SUMMARY.md](../SESSION_SUMMARY.md)** - Recent development session summary
- **[WHAT_YOULL_SEE.md](../WHAT_YOULL_SEE.md)** - Expected app behavior and features

---

## Quick Reference

### Setup Commands

```bash
# Backend
cd backend
make install
alembic upgrade head
make run

# iOS
cd ios/ClearSplit
xcodebuild -scheme ClearSplit -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Key Files

- **Backend Entry**: `backend/app/main.py`
- **iOS Entry**: `ios/ClearSplit/ClearSplit/ClearSplit/ClearSplitApp.swift`
- **Database Schema**: `docs/db.md`
- **API Docs**: Available at `http://localhost:8000/docs` when backend is running

---

## Documentation by Category

### 📚 Core Documentation

- README.md (root)
- backend/README.md
- ios/README.md
- docs/INDEX.md

### 🏗️ Architecture

- docs/adr/0001-non-negotiables.md
- docs/db.md
- SHOPPING_MODEL.md

### 💻 Implementation Guides

- backend/AUTH_IMPLEMENTATION.md
- backend/EXPENSES_IMPLEMENTATION.md
- backend/GROUPS_IMPLEMENTATION.md
- backend/MODELS_IMPLEMENTATION.md
- backend/SCHEMAS_IMPLEMENTATION.md

### 🧪 Testing

- PHASE0_VERIFICATION.md
- INTEGRATION_VERIFICATION.md
- TESTING_SUMMARY.md
- HOW_TO_TEST_SHOPPING.md

### 🔧 Troubleshooting

- BUILD_FIX_GUIDE.md
- BUILD_TROUBLESHOOTING.md
- REBUILD_IOS.md

### 🔒 Security

- SECURITY.md
- SECURITY_PATCH.md
- SECURITY_HARDENING_SUMMARY.md
- TOKEN_REFRESH_FIX.md

### 📝 Development Notes

- SESSION_SUMMARY.md
- WHAT_YOULL_SEE.md
- COMPLETE_FIX_SUMMARY.md
- BACKEND_FIX_SUMMARY.md
- PARTICIPANT_FIX_STATUS.md
- SHOPPING_IMPLEMENTATION_SUMMARY.md
- IOS_INTEGRATION_COMPLETE.md

---

*Last updated: 2026-01-27*
*Total documentation files: 25+*
