# Receipt Review Screen - SwiftUI Implementation

Modern receipt review screen with inline editing capabilities for ClearSplit iOS app.

## Overview

After a user uploads a receipt photo, this screen displays the extracted items with:
- Item name, price, and quantity
- Confidence levels (high/medium/low) for each extraction
- Inline editing capabilities
- Add/delete item functionality
- Real-time total calculation
- Receipt image preview with pinch-to-zoom

## Files Created

```
Sources/ClearSplit/
├── Models/
│   └── ExtractedItemModel.swift       # Data model for extracted items
├── Views/
│   ├── ReceiptReviewView.swift        # Main review screen
│   ├── ItemRowView.swift              # Individual item row component
│   └── ReceiptPreviewSheet.swift      # Full-screen receipt preview
└── Examples/
    └── ReceiptReviewExample.swift     # Usage examples and integration guide
```

## Key Features

### 1. **Receipt Image Preview**
- Tap photo icon in navigation bar
- Full-screen sheet with pinch-to-zoom (1x - 4x)
- Reset zoom button
- Black background for better visibility

### 2. **Item List Display**
- Circular numbered badges (1, 2, 3...)
- Shows: name, price × quantity = total
- Color-coded confidence badges:
  - 🟢 Green: High confidence
  - 🟡 Yellow: Medium confidence
  - 🟠 Orange: Low confidence (with ⚠️ warning)

### 3. **Inline Editing**
- Tap pencil icon to enter edit mode
- Edit name, price, quantity in same card
- Save or cancel actions
- Auto-focus on name field
- Haptic feedback on save

### 4. **Add New Items**
- Dashed border "Add Item" button
- Creates item with defaults
- Immediately enters edit mode

### 5. **Delete Items**
- Tap trash icon to delete
- Immediate removal with haptic feedback
- Real-time total updates

### 6. **Real-time Calculations**
- Total amount computed automatically
- Total item count updates live
- Displayed in gradient summary card

### 7. **Fixed Confirm Button**
- Always visible at bottom
- Shows count and total amount
- Disabled when items list is empty
- Triggers onConfirm callback

## Usage

### Basic Integration

```swift
import SwiftUI

ReceiptReviewView(
    receiptImage: receiptUIImage,
    sessionId: 123,
    onConfirm: { items in
        // Handle confirmed items
        print("Confirmed \(items.count) items")
        saveToBackend(items)
    },
    onBack: {
        // Handle back navigation
        dismiss()
    }
)
```

### With NavigationLink

```swift
NavigationLink("Review Receipt") {
    ReceiptReviewView(
        receiptImage: receiptImage,
        sessionId: currentSessionId,
        onConfirm: { items in
            handleConfirmedItems(items)
        },
        onBack: {
            navigationPath.removeLast()
        }
    )
}
```

### With Real OCR Data

```swift
ReceiptReviewView(
    receiptImage: receiptImage,
    sessionId: sessionId,
    extractedItems: ocrExtractedItems,  // Pass real OCR data
    onConfirm: { items in
        saveToBackend(items)
    },
    onBack: { dismiss() }
)
```

### As Sheet

```swift
@State private var showingReview = false

Button("Review Receipt") {
    showingReview = true
}
.sheet(isPresented: $showingReview) {
    NavigationView {
        ReceiptReviewView(
            receiptImage: receiptImage,
            sessionId: sessionId,
            onConfirm: { items in
                saveItems(items)
                showingReview = false
            },
            onBack: {
                showingReview = false
            }
        )
    }
}
```

## Data Model

### ExtractedItem

```swift
struct ExtractedItem: Identifiable, Codable {
    let id: String
    var name: String
    var price: Double
    var quantity: Int
    var confidence: ConfidenceLevel
    
    enum ConfidenceLevel: String, Codable {
        case high
        case medium
        case low
    }
    
    var totalPrice: Double {
        price * Double(quantity)
    }
}
```

## Backend Integration

### Save Confirmed Items

```swift
func handleConfirmedItems(_ items: [ExtractedItem]) {
    Task {
        do {
            // Convert to cents for backend
            let apiItems = items.map { item in
                ShoppingItemCreate(
                    name: item.name,
                    quantity: item.quantity,
                    unitPriceCents: Int(item.price * 100),
                    totalCents: Int(item.totalPrice * 100)
                )
            }
            
            // POST to backend
            try await api.post(
                "/shopping-sessions/\(sessionId)/items",
                body: apiItems
            )
            
            // Success
            await MainActor.run {
                navigationPath.removeLast()
            }
        } catch {
            print("Error: \(error)")
        }
    }
}
```

## Design Specifications

### Colors

```swift
// Primary Blue
Color(red: 37/255, green: 99/255, blue: 235/255)  // #2563EB

// Blue Gradient (Summary Card)
LinearGradient(
    colors: [
        Color(red: 37/255, green: 99/255, blue: 235/255),  // from-blue-600
        Color(red: 29/255, green: 78/255, blue: 216/255)   // to-blue-700
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// Confidence Colors
.green.opacity(0.15)   // High confidence background
.green.opacity(0.9)    // High confidence text
.yellow.opacity(0.15)  // Medium confidence background
.yellow.opacity(0.9)   // Medium confidence text
.orange.opacity(0.15)  // Low confidence background
.orange.opacity(0.9)   // Low confidence text
```

### Typography

```swift
// Navigation Title
.font(.headline)

// Total Amount
.font(.system(size: 36, weight: .bold))

// Item Count
.font(.system(size: 24, weight: .semibold))

// Item Name
.font(.system(size: 16, weight: .medium))

// Price Details
.font(.system(size: 14))

// Confidence Badge
.font(.system(size: 12, weight: .medium))

// Buttons
.font(.system(size: 16, weight: .semibold))
```

### Spacing & Layout

```swift
// Card Padding
.padding(24)  // Summary card
.padding(16)  // Item cards, container
.padding(12)  // Inner spacing

// Item Spacing
LazyVStack(spacing: 12)  // Between items

// Corner Radius
.cornerRadius(16)  // Cards
.cornerRadius(12)  // Buttons, badges
.cornerRadius(8)   // Input fields

// Fixed Heights
56pt  // Confirm button
60pt  // Add item button
40pt  // Edit mode buttons
32pt  // Index badge

// Bottom Safe Area
80pt  // Scroll view bottom padding
```

## Testing

Run the example:

```swift
import SwiftUI

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ReceiptReviewExample()  // Demo with all integration patterns
        }
    }
}
```

### Test Checklist

- [ ] Receipt image displays in preview sheet
- [ ] Pinch-to-zoom works (1x - 4x)
- [ ] Items list renders with all data
- [ ] Edit mode opens when tapping pencil
- [ ] Changes save correctly
- [ ] Cancel discards changes
- [ ] Delete removes item with haptic
- [ ] Add item creates new entry in edit mode
- [ ] Totals calculate correctly in real-time
- [ ] Confirm button triggers callback
- [ ] Back button navigates correctly
- [ ] Confidence badges show correct colors
- [ ] Keyboard auto-focuses on name field
- [ ] Works in light and dark mode

## iOS Requirements

- **Minimum iOS:** 15.0
- **Recommended:** iOS 16.0+ (for NavigationStack)
- **SwiftUI:** 3.0+

## Dependencies

- SwiftUI (standard)
- Foundation (standard)
- UIKit (for UIImage)

No third-party dependencies required.

## Accessibility

Current implementation includes:
- VoiceOver support (SwiftUI default)
- Dynamic Type support
- Accessibility labels on action buttons
- Sufficient color contrast
- Semantic button roles

## Next Steps

1. **Connect to OCR Service**
   - Replace mock data with real OCR results
   - Handle OCR errors gracefully

2. **Backend Integration**
   - POST items to `/shopping-sessions/{id}/items`
   - Handle network errors
   - Show loading states

3. **Enhanced Features**
   - Pull-to-refresh OCR extraction
   - Undo/redo support
   - Bulk edit mode
   - Item categories/tags

4. **Testing**
   - Unit tests for calculations
   - UI tests for user flows
   - Snapshot tests for layouts

## Related Files

- `ExtractedItemsReviewView.swift` - Original checkbox-based review (legacy)
- `ReceiptUploadView.swift` - Receipt capture screen
- `ShoppingSessionDetailView.swift` - Session detail screen

## License

Private - ClearSplit Project
