import SwiftUI

/// View for reviewing and confirming OCR-extracted items from a receipt
public struct ExtractedItemsReviewView: View {
    let sessionId: UUID
    let groupId: UUID
    let receiptUploadId: UUID
    let participants: [ShoppingSessionParticipant]
    let appState: AppState
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var extractedItems: [EditableExtractedItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isConfirming = false
    
    public var body: some View {
        NavigationView {
            ZStack {
                if isLoading {
                    ProgressView("Extracting items from receipt...")
                        .padding()
                } else if let error = error {
                    errorView(error)
                } else if extractedItems.isEmpty {
                    emptyView
                } else {
                    itemsList
                }
            }
            .navigationTitle("Review Extracted Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if !extractedItems.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") {
                            confirmItems()
                        }
                        .disabled(isConfirming || !hasSelectedItems)
                    }
                }
            }
        }
        .task {
            await loadExtractedItems()
        }
    }
    
    private var itemsList: some View {
        VStack(spacing: 0) {
            // Header with count
            HStack {
                Text("\(selectedItemsCount) of \(extractedItems.count) items selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { selectAll() }) {
                    Text("Select All")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            
            // Items list
            List {
                ForEach($extractedItems) { $item in
                    ExtractedItemRow(item: $item)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Items Found")
                .font(.headline)
            
            Text("The OCR couldn't extract any items from this receipt. You can add items manually.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Extraction Failed")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var hasSelectedItems: Bool {
        extractedItems.contains { $0.isIncluded }
    }
    
    private var selectedItemsCount: Int {
        extractedItems.filter { $0.isIncluded }.count
    }
    
    private func selectAll() {
        for index in extractedItems.indices {
            extractedItems[index].isIncluded = true
        }
    }
    
    private func loadExtractedItems() async {
        isLoading = true
        error = nil
        
        do {
            let items = try await appState.shoppingService.extractReceiptItems(
                receiptUploadId: receiptUploadId
            )
            
            extractedItems = items.map { item in
                EditableExtractedItem(
                    id: item.id,
                    name: item.name,
                    quantity: item.quantity,
                    unitPriceCents: item.unitPriceCents,
                    totalCents: item.totalCents,
                    confidence: item.confidence,
                    rawLine: item.rawLine,
                    isIncluded: true  // Include all by default
                )
            }
            
            isLoading = false
        } catch let apiError as APIError {
            // Handle specific API errors
            switch apiError {
            case .server(let status, let message) where status == 403:
                self.error = "Only the payer can extract items from receipts. \(message ?? "")"
            case .unauthorized:
                self.error = "You are not authorized. Please log in again."
            default:
                self.error = "Failed to extract items: \(apiError.localizedDescription)"
            }
            isLoading = false
        } catch {
            self.error = "Failed to extract items: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func confirmItems() {
        isConfirming = true
        
        Task {
            do {
                // Get participant membership IDs for auto-setting sharers
                let participantIds = participants.map { $0.membershipId }
                
                // Create shopping items for selected extracted items
                for item in extractedItems where item.isIncluded {
                    let createRequest = ShoppingItemCreate(
                        name: item.name,
                        quantity: item.quantity,
                        unitPriceCents: item.unitPriceCents,
                        totalCents: item.totalCents
                    )
                    
                    let createdItem = try await appState.shoppingService.createItem(
                        sessionId: sessionId,
                        request: createRequest
                    )
                    
                    // Auto-set sharers if there are participants
                    if !participantIds.isEmpty {
                        let sharersRequest = SharersSetRequest(membershipIds: participantIds)
                        _ = try await appState.shoppingService.setSharers(
                            itemId: createdItem.id,
                            request: sharersRequest
                        )
                    }
                }
                
                // Refresh the shopping session to show new items
                _ = try await appState.shoppingService.getSession(sessionId: sessionId)
                
                // Dismiss the view
                await MainActor.run {
                    isConfirming = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to create items: \(error.localizedDescription)"
                    isConfirming = false
                }
            }
        }
    }
}

// MARK: - Editable Extracted Item

private struct EditableExtractedItem: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitPriceCents: Int?
    var totalCents: Int
    let confidence: Double?
    let rawLine: String?
    var isIncluded: Bool
}

// MARK: - Extracted Item Row

private struct ExtractedItemRow: View {
    @Binding var item: EditableExtractedItem
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row with checkbox
            HStack(spacing: 12) {
                // Checkbox
                Button(action: { item.isIncluded.toggle() }) {
                    Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(item.isIncluded ? .blue : .gray)
                }
                .buttonStyle(.plain)
                
                // Item details
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .strikethrough(!item.isIncluded)
                        .foregroundColor(item.isIncluded ? .primary : .secondary)
                    
                    HStack(spacing: 12) {
                        Text("Qty: \(item.quantity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let confidence = item.confidence {
                            confidenceBadge(confidence)
                        }
                    }
                }
                
                Spacer()
                
                // Price
                Text(formatCents(item.totalCents))
                    .font(.body.weight(.medium))
                    .foregroundColor(item.isIncluded ? .primary : .secondary)
            }
            
            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    if let rawLine = item.rawLine, !rawLine.isEmpty {
                        Text("Raw: \(rawLine)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                    
                    // Editable fields
                    VStack(spacing: 12) {
                        HStack {
                            Text("Name:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Item name", text: $item.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Quantity:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Qty", value: $item.quantity, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                        }
                        
                        HStack {
                            Text("Total:")
                                .font(.caption.weight(.medium))
                                .frame(width: 60, alignment: .leading)
                            TextField("Total", value: $item.totalCents, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Text("¢")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }
    
    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color = {
            if confidence >= 0.8 { return .green }
            else if confidence >= 0.5 { return .orange }
            else { return .red }
        }()
        
        let percentage = Int(confidence * 100)
        
        return Text("\(percentage)%")
            .font(.caption2.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
    
    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
