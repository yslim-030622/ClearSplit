# Documentation Organization

This document explains how documentation files are organized in the `docs/` folder.

## 📁 Folder Structure

All documentation files (except README.md files) have been moved from the root directory into organized subfolders within `docs/`.

### Why This Structure?

- **Clean root directory** - Only essential files remain at the root
- **Easy to find** - Documentation is categorized by purpose
- **Maintainable** - New docs can be added to appropriate folders
- **Scalable** - Structure supports growth without clutter

## 📂 Folder Descriptions

### `guides/`

Setup guides, build troubleshooting, and rebuild instructions.

- BUILD_FIX_GUIDE.md
- BUILD_TROUBLESHOOTING.md
- REBUILD_IOS.md

### `features/`

Feature-specific documentation including models, implementations, and testing guides.

- SHOPPING_MODEL.md
- SHOPPING_IMPLEMENTATION_SUMMARY.md
- HOW_TO_TEST_SHOPPING.md

### `backend-docs/`

Backend implementation guides moved from `backend/` folder.

- AUTH_IMPLEMENTATION.md
- EXPENSES_IMPLEMENTATION.md
- GROUPS_IMPLEMENTATION.md
- MODELS_IMPLEMENTATION.md
- SCHEMAS_IMPLEMENTATION.md

### `testing/`

Testing guides, verification checklists, and testing summaries.

- PHASE0_VERIFICATION.md
- INTEGRATION_VERIFICATION.md
- TESTING_SUMMARY.md

### `security/`

Security documentation including overview, patches, and hardening notes.

- SECURITY.md
- SECURITY_PATCH.md
- SECURITY_HARDENING_SUMMARY.md
- TOKEN_REFRESH_FIX.md

### `development/`

Development notes, session summaries, and fix summaries.

- SESSION_SUMMARY.md
- COMPLETE_FIX_SUMMARY.md
- BACKEND_FIX_SUMMARY.md
- PARTICIPANT_FIX_STATUS.md
- IOS_INTEGRATION_COMPLETE.md
- WHAT_YOULL_SEE.md

### `architecture/`

Architecture decision records and database design documents.

- db.md
- adr/0001-non-negotiables.md

## 📝 Files That Stay in Place

The following README.md files remain in their original locations as entry points:

- `README.md` (root) - Main project overview
- `backend/README.md` - Backend setup and conventions
- `ios/README.md` - iOS setup and conventions

## 🔄 Migration Notes

All documentation files have been moved from:

- Root directory → `docs/[category]/`
- `backend/*_IMPLEMENTATION.md` → `docs/backend-docs/`

References in code and other documentation may need to be updated to reflect new paths.

## 📚 Finding Documentation

- **Quick index**: See [INDEX.md](./INDEX.md)
- **Complete list**: See [ALL_DOCUMENTATION.md](./ALL_DOCUMENTATION.md)
- **Categorized index**: See [DOCUMENTATION_INDEX.md](./DOCUMENTATION_INDEX.md)

---

*Documentation organized: 2026-01-27*
