import SwiftUI

/// Modern review screen for OCR-extracted receipt items.
public struct ExtractedItemsReviewView: View {
    let sessionId: UUID
    let groupId: UUID
    let receiptUploadId: UUID
    let participants: [ShoppingSessionParticipant]
    let appState: AppState

    @Environment(\.dismiss) private var dismiss

    @State private var items: [EditableExtractedItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isConfirming = false
    @State private var editingId: UUID?
    @State private var editForm = EditForm(name: "", price: "", quantity: "")
    @State private var showReceiptPreview = false
    @State private var receiptPreviewURL: URL?

    public var body: some View {
        ZStack(alignment: .bottom) {
            if isLoading {
                ProgressView("Extracting items from receipt...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                errorView(error)
            } else {
                content
            }

            confirmBar
        }
        .background(Color.gray50)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.gray900)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Review Items")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showReceiptPreview = true }) {
                    Image(systemName: "photo")
                        .foregroundColor(.blue600)
                }
                .disabled(receiptPreviewURL == nil)
            }
        }
        .sheet(isPresented: $showReceiptPreview) {
            if let receiptPreviewURL {
                ReceiptImagePreviewSheet(url: receiptPreviewURL)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.gray400)
                    Text("Receipt preview unavailable")
                        .foregroundColor(.gray600)
                }
                .padding()
            }
        }
        .task {
            await loadExtractedItems()
            await loadReceiptPreviewURL()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            summaryCard

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemCard(item: item, index: index + 1)
                        }
                    }

                    addItemButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 112)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Amount")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                    Text(String(format: "$%.2f", totalAmount))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Items")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(totalItems)")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Text("Review and edit the items extracted from your receipt. Items with lower confidence may need verification.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.blue600, Color.blue700],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func itemCard(item: EditableExtractedItem, index: Int) -> some View {
        VStack(spacing: 0) {
            if editingId == item.id {
                editMode(item: item)
            } else {
                viewMode(item: item, index: index)
            }
        }
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private func viewMode(item: EditableExtractedItem, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue600)
                .frame(width: 32, height: 32)
                .background(Color.blue100)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray900)
                    Spacer()
                    HStack(spacing: 8) {
                        Button(action: { startEditing(item) }) {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue600)
                        }
                        .accessibilityLabel("Edit item")

                        Button(action: { deleteItem(item.id) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .accessibilityLabel("Delete item")
                    }
                }

                HStack(spacing: 4) {
                    Text(String(format: "$%.2f × %d", item.price, item.quantity))
                        .font(.system(size: 14))
                        .foregroundColor(.gray600)
                    Text("•")
                        .foregroundColor(.gray400)
                    Text(String(format: "$%.2f", item.totalPrice))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray900)
                }

                confidenceBadge(for: item.confidenceLevel)
            }
        }
        .padding(16)
    }

    private func editMode(item: EditableExtractedItem) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Item Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray600)
                TextField("Item name", text: $editForm.name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray600)
                    HStack {
                        Text("$").foregroundColor(.gray500)
                        TextField("0.00", text: $editForm.price)
                            .keyboardType(.decimalPad)
                    }
                    .padding(8)
                    .background(Color.gray100)
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Quantity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray600)
                    TextField("1", text: $editForm.quantity)
                        .keyboardType(.numberPad)
                        .padding(8)
                        .background(Color.gray100)
                        .cornerRadius(8)
                }
            }

            HStack(spacing: 8) {
                Button(action: { saveEdit(id: item.id) }) {
                    Label("Save", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundColor(.white)
                        .background(Color.blue600)
                        .cornerRadius(8)
                }

                Button(action: cancelEdit) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .foregroundColor(.gray800)
                        .background(Color.gray100)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
    }

    private func confidenceBadge(for level: ExtractedConfidenceLevel) -> some View {
        HStack(spacing: 4) {
            if level == .low {
                Text("⚠️").font(.system(size: 10))
            }
            Text("\(level.displayName) confidence")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(level.backgroundColor)
        .foregroundColor(level.textColor)
        .cornerRadius(12)
    }

    private var addItemButton: some View {
        Button(action: addItem) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                Text("Add Item")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.gray600)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(Color.gray300)
            )
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: confirmItems) {
                HStack(spacing: 8) {
                    if isConfirming {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("Confirm \(items.count) \(items.count == 1 ? "Item" : "Items") (\(String(format: "$%.2f", totalAmount)))")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(items.isEmpty || isConfirming ? Color.gray : Color.blue600)
                .cornerRadius(12)
            }
            .disabled(items.isEmpty || isConfirming)
            .padding(16)
            .background(Color.white)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray400)
            Text("No items found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray700)
            Text("Add items manually")
                .font(.system(size: 13))
                .foregroundColor(.gray500)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundColor(.red)
            Text("Extraction Failed")
                .font(.headline)
            Text(message)
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

    private var totalAmount: Double {
        items.reduce(0) { $0 + $1.totalPrice }
    }

    private var totalItems: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    private func startEditing(_ item: EditableExtractedItem) {
        editingId = item.id
        editForm = EditForm(
            name: item.name,
            price: String(format: "%.2f", item.price),
            quantity: "\(item.quantity)"
        )
    }

    private func saveEdit(id: UUID) {
        let updatedName = editForm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedPrice = max(0, Double(editForm.price) ?? 0)
        let updatedQuantity = max(1, Int(editForm.quantity) ?? 1)

        items = items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.name = updatedName.isEmpty ? "Unnamed Item" : updatedName
            updated.price = updatedPrice
            updated.quantity = updatedQuantity
            return updated
        }
        cancelEdit()
    }

    private func cancelEdit() {
        editingId = nil
        editForm = EditForm(name: "", price: "", quantity: "")
    }

    private func addItem() {
        let newItem = EditableExtractedItem(
            id: UUID(),
            name: "New Item",
            price: 0,
            quantity: 1,
            confidenceLevel: .high
        )
        items.append(newItem)
        startEditing(newItem)
    }

    private func deleteItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        if editingId == id {
            cancelEdit()
        }
    }

    private func loadReceiptPreviewURL() async {
        do {
            let urlString = try await appState.getReceiptDownloadURL(receiptUploadId: receiptUploadId)
            await MainActor.run {
                receiptPreviewURL = URL(string: urlString)
            }
        } catch {
            // Keep preview optional; list editing should still work even if URL fetch fails.
        }
    }

    private func loadExtractedItems() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let extracted = try await appState.shoppingService.extractReceiptItems(
                receiptUploadId: receiptUploadId
            )

            let mapped = extracted.map { item in
                let quantity = max(1, item.quantity)
                let unitPriceCents = item.unitPriceCents ?? (quantity > 0 ? item.totalCents / quantity : item.totalCents)
                let price = Double(unitPriceCents) / 100.0
                return EditableExtractedItem(
                    id: item.id,
                    name: item.name,
                    price: price,
                    quantity: quantity,
                    confidenceLevel: ExtractedConfidenceLevel.from(confidence: item.confidence)
                )
            }

            await MainActor.run {
                items = mapped
                isLoading = false
            }
        } catch let apiError as APIError {
            await MainActor.run {
                switch apiError {
                case .server(let status, let message) where status == 403:
                    error = "Only the payer can extract items from receipts. \(message ?? "")"
                case .unauthorized:
                    error = "You are not authorized. Please log in again."
                default:
                    error = "Failed to extract items: \(apiError.localizedDescription)"
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to extract items: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func confirmItems() {
        isConfirming = true

        Task {
            do {
                let participantIds = participants.map { $0.membershipId }

                for item in items {
                    let qty = max(1, item.quantity)
                    let unitPriceCents = Int((item.price * 100).rounded())
                    let totalCents = Int((item.totalPrice * 100).rounded())

                    let request = ShoppingItemCreate(
                        name: item.name,
                        quantity: qty,
                        unitPriceCents: unitPriceCents,
                        totalCents: totalCents
                    )

                    let createdItem = try await appState.shoppingService.createItem(
                        sessionId: sessionId,
                        request: request
                    )

                    if !participantIds.isEmpty {
                        let sharersRequest = SharersSetRequest(membershipIds: participantIds)
                        _ = try await appState.shoppingService.setSharers(
                            itemId: createdItem.id,
                            request: sharersRequest
                        )
                    }
                }

                _ = try await appState.shoppingService.getSession(sessionId: sessionId)

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

private struct EditForm {
    var name: String
    var price: String
    var quantity: String
}

private struct EditableExtractedItem: Identifiable {
    let id: UUID
    var name: String
    var price: Double
    var quantity: Int
    var confidenceLevel: ExtractedConfidenceLevel

    var totalPrice: Double {
        price * Double(quantity)
    }
}

private enum ExtractedConfidenceLevel {
    case high
    case medium
    case low

    static func from(confidence: Double?) -> ExtractedConfidenceLevel {
        guard let confidence else { return .medium }
        if confidence >= 0.8 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
    }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .high: return .green.opacity(0.15)
        case .medium: return .yellow.opacity(0.15)
        case .low: return .orange.opacity(0.15)
        }
    }

    var textColor: Color {
        switch self {
        case .high: return .green.opacity(0.9)
        case .medium: return .yellow.opacity(0.9)
        case .low: return .orange.opacity(0.9)
        }
    }
}

private struct ReceiptImagePreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding()
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundColor(.gray)
                            Text("Failed to load receipt image")
                                .foregroundColor(.gray)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
