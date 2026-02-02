# ClearSplitApp.swift Modularization Plan

## Current State
- File size: 4957 lines
- Contains: Models, Views, ViewModels, AppState, Utilities, Design System

## Extraction Strategy

### ✅ Completed
1. **Models** → `Sources/ClearSplit/Models/`
   - AuthModels.swift (User, AuthTokens, LoginRequest, etc.)
   - GroupModels.swift (Group, Membership, MemberPreview)
   - ShoppingModels.swift (ShoppingSession, ShoppingItem, etc.)
   - SettlementModels.swift (Settlement, SettlementBatch)
   - ExpenseModels.swift (Expense, CreateExpenseRequest)

2. **Utilities** → `Sources/ClearSplit/Utilities/`
   - Formatting.swift (formatCurrency, formatDateString, parseDateString)

3. **Design System** → `Sources/ClearSplit/DesignSystem/`
   - Colors.swift (Color extensions and design tokens)
   - ButtonStyles.swift (ScaleButtonStyle)

### 🔄 In Progress
4. **Views** → `Sources/ClearSplit/Views/`
   - GroupDetailView.swift (with all subviews)
   - ShoppingSessionCard.swift (with skeleton)
   - ShoppingSessionsHelpSheet.swift
   - AddMemberDialog.swift (with result cards)

### 📋 Remaining
5. **AppState** → Keep in ClearSplitApp.swift for now (or move to State/AppState.swift)
6. **Configuration** → Extract APIConfig to Config/
7. **Update ClearSplitApp.swift** → Minimal file with just @main App and RootView

## File Structure After Modularization

```
ClearSplitApp.swift (minimal, ~100 lines)
  - @main App
  - RootView
  - Imports all modules

Sources/ClearSplit/
  ├── Models/
  │   ├── AuthModels.swift
  │   ├── GroupModels.swift
  │   ├── ShoppingModels.swift
  │   ├── SettlementModels.swift
  │   └── ExpenseModels.swift
  ├── Views/
  │   ├── GroupDetailView.swift
  │   ├── ShoppingSessionCard.swift
  │   ├── AddMemberDialog.swift
  │   └── ... (other views)
  ├── DesignSystem/
  │   ├── Colors.swift
  │   └── ButtonStyles.swift
  ├── Utilities/
  │   └── Formatting.swift
  └── State/
      └── AppState.swift (if extracted)
```
