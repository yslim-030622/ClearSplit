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
    @State private var loadRequestVersion = 0
    @State private var editingItem: EditableExtractedItem?
    @State private var showingAddSheet = false
    @State private var itemToDelete: EditableExtractedItem?

    private var totalAmountCents: Int {
        extractedItems.reduce(0) { $0 + $1.totalCents }
    }

    private var totalAmountText: String {
        formatCurrency(cents: totalAmountCents, currency: "USD")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                content

                if !isLoading && error == nil {
                    VStack {
                        Spacer()
                        confirmButton
                    }
                }
            }
            .navigationTitle("Review Items")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                        .foregroundColor(.brandPrimary)
                    }
                }
            }
        }
        .task(id: receiptUploadId) {
            await loadExtractedItems()
        }
        .sheet(item: $editingItem) { item in
            EditExtractedItemSheet(item: item) { updatedItem in
                if let index = extractedItems.firstIndex(where: { $0.id == updatedItem.id }) {
                    extractedItems[index] = updatedItem
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddExtractedItemSheet { newItem in
                extractedItems.append(newItem)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .alert(
            "Delete Item",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let deleteId = itemToDelete?.id else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    extractedItems.removeAll { $0.id == deleteId }
                }
                itemToDelete = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } message: {
            Text("Are you sure you want to delete \"\(itemToDelete?.name ?? "this item")\"?")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Extracting items from receipt...")
                .padding()
        } else if let error {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.orange)

                Text("Extraction Failed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(error)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button("Back") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Retry") {
                        Task { await loadExtractedItems() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        } else {
            VStack(spacing: 0) {
                headerSection

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.sm) {
                        itemsSectionHeader

                        if extractedItems.isEmpty {
                            emptyItemsCard
                        } else {
                            VStack(spacing: ClearSplitTheme.Spacing.sm) {
                                ForEach(Array(extractedItems.enumerated()), id: \.element.id) { index, item in
                                    ExtractedReviewItemCard(
                                        item: item,
                                        index: index + 1,
                                        onEdit: {
                                            editingItem = item
                                        },
                                        onDelete: {
                                            itemToDelete = item
                                        }
                                    )
                                }
                            }
                        }

                        addItemButton
                    }
                    .padding(ClearSplitTheme.Spacing.md)
                    .sectionStyle()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total Amount")
                        .font(ClearSplitTheme.Typography.overline)
                        .textCase(.uppercase)
                        .tracking(ClearSplitTheme.Tracking.extraWide)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 8)

                    AnimatingCurrencyText(
                        value: totalAmountCents,
                        currency: "USD",
                        font: ClearSplitTheme.Typography.currencyHero,
                        tracking: ClearSplitTheme.Tracking.tight,
                        color: .white
                    )
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("Items")
                        .font(ClearSplitTheme.Typography.overline)
                        .textCase(.uppercase)
                        .tracking(ClearSplitTheme.Tracking.extraWide)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 8)

                    Text("\(extractedItems.count)")
                        .font(ClearSplitTheme.Typography.currencyLarge)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))

                Text("Review and edit the items extracted from your receipt. Items with lower confidence may need verification.")
                    .font(ClearSplitTheme.Typography.footnote)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ClearSplitTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ClearSplitTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.brandPrimary, Color.brandPrimaryPressed],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(ClearSplitTheme.Radius.xl + 4, corners: [.bottomLeft, .bottomRight])
    }

    private var itemsSectionHeader: some View {
        HStack(alignment: .center) {
            Text("Items")
                .font(ClearSplitTheme.Typography.sectionTitle)
                .foregroundColor(.textPrimary)

            Spacer()

            Text("\(extractedItems.count)")
                .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                .foregroundColor(.textSecondary)
                .frame(minWidth: 24, minHeight: 24)
                .padding(.horizontal, 6)
                .background(Color.gray100)
                .clipShape(Circle())
        }
        .padding(.bottom, 4)
    }

    private var emptyItemsCard: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(.textTertiary)
            Text("No items extracted yet")
                .font(ClearSplitTheme.Typography.bodyStrong)
                .foregroundColor(.textPrimary)
            Text("Add an item manually to continue.")
                .font(ClearSplitTheme.Typography.footnote)
                .foregroundColor(.textSecondary)
        }
        .padding(ClearSplitTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .itemCardStyle()
    }

    private var addItemButton: some View {
        Button(action: { showingAddSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                Text("Add Item")
                    .font(ClearSplitTheme.Typography.bodyStrong)
            }
            .foregroundColor(.textOnBrand)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryActionButtonStyle())
    }

    private var confirmButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.pageBackground.opacity(0), Color.pageBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 30)

            Button(action: confirmItems) {
                HStack(spacing: 8) {
                    if isConfirming {
                        ProgressView()
                            .tint(.textOnBrand)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                    }

                    Text("Confirm \(extractedItems.count) \(extractedItems.count == 1 ? "Item" : "Items") (\(totalAmountText))")
                        .font(ClearSplitTheme.Typography.bodyStrong)
                }
                .foregroundColor(.textOnBrand)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(extractedItems.isEmpty ? Color.textMuted : Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
            }
            .disabled(extractedItems.isEmpty || isConfirming)
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(Color.pageBackground)
        }
    }

    @MainActor
    private func loadExtractedItems() async {
        loadRequestVersion += 1
        let requestVersion = loadRequestVersion

        isLoading = true
        error = nil

        do {
            let items = try await appState.shoppingService.extractReceiptItems(
                receiptUploadId: receiptUploadId
            )

            guard requestVersion == loadRequestVersion else { return }

            extractedItems = items.map { item in
                EditableExtractedItem(
                    id: item.id,
                    name: item.name,
                    quantity: item.quantity,
                    unitPriceCents: item.unitPriceCents,
                    totalCents: item.totalCents,
                    confidence: item.confidence,
                    rawLine: item.rawLine,
                    isIncluded: true
                )
            }

            error = nil
            isLoading = false
        } catch {
            guard requestVersion == loadRequestVersion else { return }

            if isCancellation(error) {
                return
            }

            if let apiError = error as? APIError {
                switch apiError {
                case .server(let status, let message) where status == 403:
                    self.error = "Only the receipt uploader can extract items. \(message ?? "")"
                case .unauthorized:
                    self.error = "You are not authorized. Please log in again."
                default:
                    self.error = "Failed to extract items: \(apiError.localizedDescription)"
                }
            } else {
                self.error = "Failed to extract items: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        if let apiError = error as? APIError,
           case .network(let underlyingError) = apiError {
            if underlyingError is CancellationError {
                return true
            }
            if let urlError = underlyingError as? URLError, urlError.code == .cancelled {
                return true
            }
            let nsError = underlyingError as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func confirmItems() {
        guard !extractedItems.isEmpty else { return }
        isConfirming = true

        Task {
            do {
                let participantIds = participants.map { $0.membershipId }

                for item in extractedItems {
                    let quantity = max(1, item.quantity)
                    let resolvedUnitPriceCents = item.unitPriceCents ?? {
                        guard quantity > 0 else { return item.totalCents }
                        return Int((Double(item.totalCents) / Double(quantity)).rounded())
                    }()
                    let totalCents = max(0, item.totalCents)
                    let createRequest = ShoppingItemCreate(
                        name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        quantity: quantity,
                        unitPriceCents: resolvedUnitPriceCents,
                        totalCents: totalCents
                    )

                    let createdItem = try await appState.shoppingService.createItem(
                        sessionId: sessionId,
                        request: createRequest
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to create items: \(error.localizedDescription)"
                    isConfirming = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

private enum ExtractedItemConfidenceLevel: String, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        }
    }

    var badgeBackground: Color {
        switch self {
        case .high:
            return Color.successSurface
        case .medium:
            return Color.warningSurface
        case .low:
            return Color.dangerSurface
        }
    }

    var badgeText: Color {
        switch self {
        case .high:
            return Color.success
        case .medium:
            return Color.warning
        case .low:
            return Color.danger
        }
    }

    var requiresWarning: Bool {
        self == .low
    }

    var representativeConfidence: Double {
        switch self {
        case .high: return 0.95
        case .medium: return 0.65
        case .low: return 0.35
        }
    }

    static func from(_ confidence: Double?) -> ExtractedItemConfidenceLevel {
        guard let confidence else { return .medium }
        if confidence >= 0.8 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
    }
}

private extension EditableExtractedItem {
    var resolvedUnitPriceCents: Int {
        if let unitPriceCents {
            return unitPriceCents
        }
        guard quantity > 0 else { return totalCents }
        return Int((Double(totalCents) / Double(quantity)).rounded())
    }

    var confidenceLevel: ExtractedItemConfidenceLevel {
        ExtractedItemConfidenceLevel.from(confidence)
    }

    var priceBreakdownText: String {
        let unitText = formatCurrency(cents: resolvedUnitPriceCents, currency: "USD")
        let totalText = formatCurrency(cents: totalCents, currency: "USD")
        return "\(unitText) × \(quantity) = \(totalText)"
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }

        // Remove trailing "$"
        let withoutTrailingCurrency = trimmed.replacingOccurrences(
            of: #"\s*\$$"#, with: "", options: .regularExpression
        )

        // Remove leading quantity prefix (e.g. "1 ")
        let quantityPrefix = "\(quantity) "
        if withoutTrailingCurrency.hasPrefix(quantityPrefix) {
            return String(withoutTrailingCurrency.dropFirst(quantityPrefix.count))
        }

        return withoutTrailingCurrency
    }
}

private struct ExtractedReviewItemCard: View {
    let item: EditableExtractedItem
    let index: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: ClearSplitTheme.Spacing.sm) {
            // Index badge
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 28, height: 28)

                Text("\(index)")
                    .font(ClearSplitTheme.Typography.label)
                    .foregroundColor(.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Name + Price
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayName)
                        .font(ClearSplitTheme.Typography.bodyStrong)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                        .font(ClearSplitTheme.Typography.currencyBody)
                        .tracking(ClearSplitTheme.Tracking.wide)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                }

                // Price breakdown (only if qty > 1)
                if item.quantity > 1 {
                    Text(item.priceBreakdownText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.textSecondary)
                }

                // Confidence badge + Action buttons
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        if item.confidenceLevel.requiresWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Text(item.confidenceLevel.title)
                            .font(ClearSplitTheme.Typography.overline)
                    }
                    .foregroundColor(item.confidenceLevel.badgeText)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(item.confidenceLevel.badgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    HStack(spacing: 4) {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onEdit()
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue500)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDelete()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red500)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .itemCardStyle()
    }
}

private struct EditExtractedItemSheet: View {
    let item: EditableExtractedItem
    let onSave: (EditableExtractedItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var unitPriceText: String
    @State private var quantity: Int
    @State private var confidenceLevel: ExtractedItemConfidenceLevel

    init(item: EditableExtractedItem, onSave: @escaping (EditableExtractedItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _unitPriceText = State(initialValue: String(format: "%.2f", Double(item.resolvedUnitPriceCents) / 100.0))
        _quantity = State(initialValue: max(item.quantity, 1))
        _confidenceLevel = State(initialValue: item.confidenceLevel)
    }

    private var unitPrice: Double {
        Double(unitPriceText) ?? 0
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        unitPrice > 0 &&
        quantity > 0
    }

    private var totalAmount: Double {
        unitPrice * Double(quantity)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    HStack(spacing: 8) {
                        Text("$")
                            .foregroundColor(.textSecondary)
                        TextField("0.00", text: $unitPriceText)
                            .keyboardType(.decimalPad)
                    }

                    Stepper(value: $quantity, in: 1...999) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                Section("Confidence") {
                    Picker("Confidence", selection: $confidenceLevel) {
                        ForEach(ExtractedItemConfidenceLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("Total")
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text(String(format: "$%.2f", totalAmount))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let unitPriceCents = Int((unitPrice * 100).rounded())
        let updatedItem = EditableExtractedItem(
            id: item.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            totalCents: unitPriceCents * quantity,
            confidence: confidenceLevel.representativeConfidence,
            rawLine: item.rawLine,
            isIncluded: item.isIncluded
        )

        onSave(updatedItem)
        dismiss()
    }
}

private struct AddExtractedItemSheet: View {
    let onAdd: (EditableExtractedItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unitPriceText = ""
    @State private var quantity = 1
    @State private var confidenceLevel: ExtractedItemConfidenceLevel = .high

    private var unitPrice: Double {
        Double(unitPriceText) ?? 0
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        unitPrice > 0 &&
        quantity > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    HStack(spacing: 8) {
                        Text("$")
                            .foregroundColor(.textSecondary)
                        TextField("0.00", text: $unitPriceText)
                            .keyboardType(.decimalPad)
                    }

                    Stepper(value: $quantity, in: 1...999) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }

                Section("Confidence") {
                    Picker("Confidence", selection: $confidenceLevel) {
                        ForEach(ExtractedItemConfidenceLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func add() {
        let unitPriceCents = Int((unitPrice * 100).rounded())
        let newItem = EditableExtractedItem(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            totalCents: unitPriceCents * quantity,
            confidence: confidenceLevel.representativeConfidence,
            rawLine: nil,
            isIncluded: true
        )
        onAdd(newItem)
        dismiss()
    }
}
