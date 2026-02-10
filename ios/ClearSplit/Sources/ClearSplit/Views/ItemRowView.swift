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
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                // Item Name
                HStack {
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Action Buttons
                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Edit \(item.name)")
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Delete \(item.name)")
                    }
                }
                
                // Price Details
                HStack(spacing: 4) {
                    Text("$\(item.price, specifier: "%.2f") × \(item.quantity)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("$\(item.totalPrice, specifier: "%.2f")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Item name", text: $editName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .name)
            }
            
            // Price and Quantity
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $editPrice)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(8)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quantity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("1", text: $editQuantity)
                        .keyboardType(.numberPad)
                        .padding(8)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
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
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    focusedField = nil
                    onCancel()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(8)
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
        case .high: return Color.green.opacity(0.15)
        case .medium: return Color.yellow.opacity(0.15)
        case .low: return Color.orange.opacity(0.15)
        }
    }
    
    private var confidenceForegroundColor: Color {
        switch item.confidence {
        case .high: return Color.green.opacity(0.9)
        case .medium: return Color.yellow.opacity(0.9)
        case .low: return Color.orange.opacity(0.9)
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
        .background(Color(UIColor.systemGroupedBackground))
    }
}
