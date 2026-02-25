import SwiftUI

/// Modern receipt review screen with inline editing capabilities
struct ReceiptReviewView: View {
    // MARK: - Properties
    let receiptImage: UIImage
    let sessionId: Int?
    let extractedItems: [ExtractedItem]?
    let onConfirm: ([ExtractedItem]) -> Void
    let onBack: () -> Void
    
    @State private var items: [ExtractedItem]
    @State private var editingItem: ExtractedItem?
    @State private var showReceiptPreview = false
    
    // MARK: - Initialization
    init(
        receiptImage: UIImage,
        sessionId: Int? = nil,
        extractedItems: [ExtractedItem]? = nil,
        onConfirm: @escaping ([ExtractedItem]) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.receiptImage = receiptImage
        self.sessionId = sessionId
        self.extractedItems = extractedItems
        self.onConfirm = onConfirm
        self.onBack = onBack
        
        // Use provided items or mock data
        self._items = State(initialValue: extractedItems ?? Self.mockExtractedItems)
    }
    
    // MARK: - Computed Properties
    private var totalAmount: Double {
        items.reduce(0) { $0 + $1.totalPrice }
    }
    
    private var totalItems: Int {
        items.reduce(0) { $0 + $1.quantity }
    }
    
    // MARK: - Mock Data
    private static let mockExtractedItems: [ExtractedItem] = [
        ExtractedItem(id: "1", name: "Organic Milk", price: 6.99, quantity: 2, confidence: .high),
        ExtractedItem(id: "2", name: "Sourdough Bread", price: 5.49, quantity: 1, confidence: .high),
        ExtractedItem(id: "3", name: "Cherry Tomatoes", price: 4.99, quantity: 1, confidence: .medium),
        ExtractedItem(id: "4", name: "Greek Yogurt", price: 7.99, quantity: 3, confidence: .high),
        ExtractedItem(id: "5", name: "Avocados", price: 1.49, quantity: 6, confidence: .low),
        ExtractedItem(id: "6", name: "Pasta Sauce", price: 3.99, quantity: 2, confidence: .medium),
    ]
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Summary Card
                summaryCard
                
                // Items List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ItemRowView(
                                item: item,
                                index: index + 1,
                                isEditing: editingItem?.id == item.id,
                                onEdit: { editingItem = item },
                                onDelete: { deleteItem(item) },
                                onSave: { updatedItem in
                                    saveEdit(updatedItem)
                                },
                                onCancel: { editingItem = nil }
                            )
                        }
                        
                        // Add Item Button
                        addItemButton
                    }
                    .padding(16)
                    .padding(.bottom, 80) // Space for fixed button
                }
                .background { AppBackground() }
            }

            // Fixed Confirm Button
            confirmButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.textPrimary)
                }
            }
            
            ToolbarItem(placement: .principal) {
                Text("Review Items")
                    .font(.headline)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showReceiptPreview = true }) {
                    Image(systemName: "photo")
                        .foregroundColor(.brandPrimary)
                }
            }
        }
        .sheet(isPresented: $showReceiptPreview) {
            ReceiptPreviewSheet(image: receiptImage)
        }
    }
    
    // MARK: - Summary Card
    private var summaryCard: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 37/255, green: 99/255, blue: 235/255),
                    Color(red: 29/255, green: 78/255, blue: 216/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Amount")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text("$\(totalAmount, specifier: "%.2f")")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Items")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text("\(totalItems)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                HStack {
                    Text("Review and edit the items extracted from your receipt. Items with lower confidence may need verification.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
            }
            .padding(24)
        }
    }
    
    // MARK: - Add Item Button
    private var addItemButton: some View {
        Button(action: addItem) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                
                Text("Add Item")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(Color.borderMedium)
            )
        }
        .accessibilityLabel("Add new item")
    }
    
    // MARK: - Confirm Button
    private var confirmButton: some View {
        VStack(spacing: 0) {
            Divider()
            
            Button(action: { onConfirm(items) }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Confirm \(items.count) \(items.count == 1 ? "Item" : "Items") ($\(totalAmount, specifier: "%.2f"))")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(items.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(items.isEmpty)
            .padding(16)
            .background(Color.cardBackground)
        }
    }
    
    // MARK: - Actions
    private func deleteItem(_ item: ExtractedItem) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        withAnimation {
            items.removeAll { $0.id == item.id }
        }
    }
    
    private func saveEdit(_ updatedItem: ExtractedItem) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
            items[index] = updatedItem
        }
        editingItem = nil
    }
    
    private func addItem() {
        let newItem = ExtractedItem(
            id: UUID().uuidString,
            name: "New Item",
            price: 0,
            quantity: 1,
            confidence: .high
        )
        items.append(newItem)
        editingItem = newItem
    }
}

// MARK: - Preview
struct ReceiptReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ReceiptReviewView(
                receiptImage: UIImage(systemName: "doc.text.image")!,
                sessionId: 1,
                onConfirm: { items in
                    print("Confirmed \(items.count) items")
                },
                onBack: {
                    print("Back pressed")
                }
            )
        }
    }
}
