import SwiftUI

/// Individual item row with view and edit modes
struct ItemRowView: View {
    let item: ExtractedItem
    let index: Int
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSave: (ExtractedItem) -> Void
    let onCancel: () -> Void
    
    @State private var editName: String = ""
    @State private var editPrice: String = ""
    @State private var editQuantity: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, price, quantity
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                editMode
            } else {
                viewMode
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
        .applyElevation(.low)
        .onAppear {
            editName = item.name
            editPrice = String(format: "%.2f", item.price)
            editQuantity = "\(item.quantity)"
        }
    }
    
    // MARK: - View Mode
    private var viewMode: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index Badge
            Text("\(index)")
                .font(ClearSplitTheme.Typography.subheadline.weight(.semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 32, height: 32)
                .background(Color.brandSubtle)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                // Item Name
                HStack {
                    Text(item.name)
                        .font(ClearSplitTheme.Typography.bodyStrong)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.brandPrimary)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Edit \(item.name)")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.danger)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Delete \(item.name)")
                    }
                }
                
                // Price Details
                HStack(spacing: 4) {
                    Text("$\(item.price, specifier: "%.2f") × \(item.quantity)")
                        .font(ClearSplitTheme.Typography.subheadline)
                        .foregroundColor(.textTertiary)
                    
                    Text("•")
                        .foregroundColor(.textTertiary)
                    
                    Text("$\(item.totalPrice, specifier: "%.2f")")
                        .font(ClearSplitTheme.Typography.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                }
                
                // Confidence Badge
                HStack(spacing: 4) {
                    if item.confidence.needsWarning {
                        Text("⚠️")
                            .font(.system(size: 10))
                    }
                    
                    Text("\(item.confidence.displayName) confidence")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(confidenceBackgroundColor)
                .foregroundColor(confidenceForegroundColor)
                .cornerRadius(12)
            }
        }
        .padding(16)
    }
    
    // MARK: - Edit Mode
    private var editMode: some View {
        VStack(spacing: 12) {
            // Item Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Item Name")
                    .font(ClearSplitTheme.Typography.caption.weight(.medium))
                    .foregroundColor(.textTertiary)
                
                TextField("Item name", text: $editName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .name)
            }
            
            // Price and Quantity
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price")
                        .font(ClearSplitTheme.Typography.caption.weight(.medium))
                        .foregroundColor(.textTertiary)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.textTertiary)
                        TextField("0.00", text: $editPrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(8)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quantity")
                        .font(ClearSplitTheme.Typography.caption.weight(.medium))
                        .foregroundColor(.textTertiary)
                    
                    TextField("1", text: $editQuantity)
                        .keyboardType(.numberPad)
                        .padding(8)
                        .background(Color.cardInset)
                        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                        .focused($focusedField, equals: .quantity)
                }
            }
            
            // Save/Cancel Buttons
            HStack(spacing: 8) {
                Button(action: {
                    focusedField = nil
                    let updatedItem = ExtractedItem(
                        id: item.id,
                        name: editName.isEmpty ? "Unnamed Item" : editName,
                        price: Double(editPrice) ?? 0,
                        quantity: max(1, Int(editQuantity) ?? 1),
                        confidence: item.confidence
                    )
                    onSave(updatedItem)
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14))
                        Text("Save")
                            .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                    }
                    .foregroundColor(.textOnBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                }
                
                Button(action: {
                    focusedField = nil
                    onCancel()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                        Text("Cancel")
                            .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                    }
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                }
            }
        }
        .padding(16)
        .onAppear {
            // Auto-focus name field when entering edit mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .name
            }
        }
    }
    
    // MARK: - Helper Properties
    private var confidenceBackgroundColor: Color {
        switch item.confidence {
        case .high: return Color.successSurface
        case .medium: return Color.warningSurface
        case .low: return Color.dangerSurface
        }
    }
    
    private var confidenceForegroundColor: Color {
        switch item.confidence {
        case .high: return Color.success
        case .medium: return Color.warning
        case .low: return Color.danger
        }
    }
}

// MARK: - Preview
struct ItemRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // View Mode
            ItemRowView(
                item: ExtractedItem(
                    id: "1",
                    name: "Organic Milk",
                    price: 6.99,
                    quantity: 2,
                    confidence: .high
                ),
                index: 1,
                isEditing: false,
                onEdit: {},
                onDelete: {},
                onSave: { _ in },
                onCancel: {}
            )
            
            // Edit Mode
            ItemRowView(
                item: ExtractedItem(
                    id: "2",
                    name: "Avocados",
                    price: 1.49,
                    quantity: 6,
                    confidence: .low
                ),
                index: 2,
                isEditing: true,
                onEdit: {},
                onDelete: {},
                onSave: { _ in },
                onCancel: {}
            )
        }
        .padding()
        .background(Color.pageBackground)
    }
}
