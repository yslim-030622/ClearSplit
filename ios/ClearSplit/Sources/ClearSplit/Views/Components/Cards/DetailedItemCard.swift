import SwiftUI

struct DetailedItemCard: View {
    let item: ShoppingItem
    let participantMembershipIds: [UUID]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onSaveEdit: (ShoppingItem, ShoppingItemCreate, [UUID]) async -> String?
    let onDelete: () -> Void

    private struct ShareParticipant: Identifiable {
        let id: UUID
        let displayName: String
        let isCurrentUser: Bool
    }

    @State private var isEditing = false
    @State private var editName: String
    @State private var editUnitPriceText: String
    @State private var editQuantity: Int
    @State private var selectedMembershipIds: Set<UUID>
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var isHovered = false

    init(
        item: ShoppingItem,
        participantMembershipIds: [UUID],
        groupMemberships: [Membership],
        currentUserId: UUID?,
        onSaveEdit: @escaping (ShoppingItem, ShoppingItemCreate, [UUID]) async -> String?,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.participantMembershipIds = participantMembershipIds
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
        self.onSaveEdit = onSaveEdit
        self.onDelete = onDelete

        let fallbackUnitPriceCents: Int
        if let unitPriceCents = item.unitPriceCents {
            fallbackUnitPriceCents = unitPriceCents
        } else if item.quantity > 0 {
            fallbackUnitPriceCents = Int((Double(item.totalCents) / Double(item.quantity)).rounded())
        } else {
            fallbackUnitPriceCents = item.totalCents
        }

        _editName = State(initialValue: Self.sanitizedItemName(item.name, quantity: item.quantity))
        _editUnitPriceText = State(initialValue: String(format: "%.2f", Double(fallbackUnitPriceCents) / 100.0))
        _editQuantity = State(initialValue: max(item.quantity, 1))

        let initialMembershipIds = Set(item.splits.map { $0.membershipId })
        if initialMembershipIds.isEmpty {
            _selectedMembershipIds = State(initialValue: Set(participantMembershipIds))
        } else {
            _selectedMembershipIds = State(initialValue: initialMembershipIds)
        }
    }

    private var currentMembershipId: UUID? {
        groupMemberships.first(where: { $0.user?.id == currentUserId })?.id
    }

    private var resolvedUnitPriceCents: Int {
        if let unitPriceCents = item.unitPriceCents {
            return unitPriceCents
        }
        guard item.quantity > 0 else { return item.totalCents }
        return Int((Double(item.totalCents) / Double(item.quantity)).rounded())
    }

    private var displayItemName: String {
        Self.sanitizedItemName(item.name, quantity: item.quantity)
    }

    private var priceBreakdown: String {
        "\(formatCurrency(cents: resolvedUnitPriceCents, currency: "USD")) × \(item.quantity)"
    }

    private var yourShareCents: Int {
        guard let currentMembershipId else { return 0 }
        return item.splits.first(where: { $0.membershipId == currentMembershipId })?.shareCents ?? 0
    }

    private var sharedByParticipants: [ShareParticipant] {
        item.splits.map { participant(from: $0.membershipId) }
    }

    private var availableParticipants: [ShareParticipant] {
        participantMembershipIds.map { participant(from: $0) }
    }

    private var resolvedEditUnitPriceCents: Int {
        Int(((Double(editUnitPriceText) ?? 0.0) * 100.0).rounded())
    }

    private var canSaveInline: Bool {
        let hasValidParticipantSelection = availableParticipants.isEmpty || !selectedMembershipIds.isEmpty
        return !editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        resolvedEditUnitPriceCents > 0 &&
        editQuantity > 0 &&
        hasValidParticipantSelection &&
        !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topSection

            if isEditing {
                inlineEditor
            } else {
                if item.quantity > 1 {
                    priceBreakdownRow
                }
                sharedBySection
                yourShareRow
            }
        }
        .padding(16)
        .itemCardStyle(isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayItemName)
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.gray900)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                    .font(ClearSplitTheme.Typography.currencyBody)
                    .tracking(ClearSplitTheme.Tracking.wide)
                    .foregroundColor(.gray900)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !isEditing {
                HStack(spacing: 0) {
                    Spacer()
                    actionButtons
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if isEditing {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cancelInlineEdit()
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray500)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel editing")
            } else {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    startInlineEdit()
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue500)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit item")
                .accessibilityHint("Edit this item inline")

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
                .accessibilityLabel("Delete item")
                .accessibilityHint("Double tap to delete this item")
            }
        }
    }

    private var priceBreakdownRow: some View {
        Text(priceBreakdown)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.gray600)
    }

    private var sharedBySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.bottom, 8)

            if sharedByParticipants.isEmpty {
                HStack(spacing: 6) {
                    Text("Shared by:")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray600)
                    Text("No participants")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray400)
                        .italic()
                }
            } else {
                FlowLayout(spacing: 6) {
                    Text("Shared by:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray600)
                        .padding(.vertical, ClearSplitTheme.Spacing.xs - 1)

                    ForEach(sharedByParticipants) { participant in
                        ParticipantPill(
                            title: participant.displayName,
                            isCurrentUser: participant.isCurrentUser
                        )
                    }
                }
            }
        }
    }

    private var yourShareRow: some View {
        HStack(spacing: 0) {
            Spacer()
            Text("Your share:")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray600)
            Text("  ")
            Text(formatCurrency(cents: yourShareCents, currency: "USD"))
                .font(ClearSplitTheme.Typography.currencyBody)
                .tracking(ClearSplitTheme.Tracking.wide)
                .foregroundColor(.gray900)
        }
        .padding(.horizontal, ClearSplitTheme.Spacing.sm)
        .padding(.vertical, ClearSplitTheme.Spacing.xs)
        .background(Color.cardInset)
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
    }

    private var inlineEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Item Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray600)

                TextField("Item name", text: $editName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit Price")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray600)

                    HStack(spacing: 6) {
                        Text("$")
                            .foregroundColor(.gray600)
                        TextField("0.00", text: $editUnitPriceText)
                            .keyboardType(.decimalPad)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quantity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray600)

                    Stepper(value: $editQuantity, in: 1...999) {
                        Text("\(editQuantity)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray900)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Shared With")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray600)

                if availableParticipants.isEmpty {
                    Text("No participants")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray400)
                        .italic()
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(availableParticipants) { participant in
                            Button(action: {
                                toggleMembership(participant.id)
                            }) {
                                HStack(spacing: 4) {
                                    if selectedMembershipIds.contains(participant.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    Text(participant.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(selectedMembershipIds.contains(participant.id) ? .blue500 : .gray600)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    selectedMembershipIds.contains(participant.id)
                                        ? Color.blue500.opacity(0.12)
                                        : Color.cardInset
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red600)
            }

            HStack(spacing: 8) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    cancelInlineEdit()
                }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray700)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.gray100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: saveInlineEdit) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    } else {
                        Text("Save Changes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                }
                .background(canSaveInline ? Color.blue500 : Color.gray400)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .disabled(!canSaveInline)
            }
        }
    }

    private func participant(from membershipId: UUID) -> ShareParticipant {
        let isCurrentUser = membershipId == currentMembershipId

        if isCurrentUser {
            return ShareParticipant(id: membershipId, displayName: "You", isCurrentUser: true)
        }

        if let membership = groupMemberships.first(where: { $0.id == membershipId }),
           let user = membership.user {
            let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
            let displayName = fullName.isEmpty ? user.displayName : fullName
            return ShareParticipant(id: membershipId, displayName: displayName, isCurrentUser: false)
        }

        return ShareParticipant(
            id: membershipId,
            displayName: "Member \(membershipId.uuidString.prefix(4).uppercased())",
            isCurrentUser: false
        )
    }

    private func startInlineEdit() {
        resetDraftFromItem()
        saveErrorMessage = nil
        isEditing = true
    }

    private func cancelInlineEdit() {
        resetDraftFromItem()
        saveErrorMessage = nil
        isEditing = false
    }

    private func resetDraftFromItem() {
        editName = Self.sanitizedItemName(item.name, quantity: item.quantity)
        editQuantity = max(item.quantity, 1)
        editUnitPriceText = String(format: "%.2f", Double(resolvedUnitPriceCents) / 100.0)

        let splitMembershipIds = Set(item.splits.map { $0.membershipId })
        if splitMembershipIds.isEmpty {
            selectedMembershipIds = Set(participantMembershipIds)
        } else {
            selectedMembershipIds = splitMembershipIds
        }
    }

    private func toggleMembership(_ membershipId: UUID) {
        if selectedMembershipIds.contains(membershipId) {
            selectedMembershipIds.remove(membershipId)
        } else {
            selectedMembershipIds.insert(membershipId)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveInlineEdit() {
        guard canSaveInline else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSaving = true
        saveErrorMessage = nil

        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let quantity = max(editQuantity, 1)
        let unitPriceCents = resolvedEditUnitPriceCents
        let totalCents = unitPriceCents * quantity
        let request = ShoppingItemCreate(
            name: trimmedName,
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            totalCents: totalCents
        )

        let membershipIds: [UUID]
        if availableParticipants.isEmpty {
            membershipIds = item.splits.map { $0.membershipId }
        } else {
            membershipIds = Array(selectedMembershipIds)
        }

        Task {
            let errorMessage = await onSaveEdit(item, request, membershipIds)
            await MainActor.run {
                isSaving = false
                if let errorMessage {
                    saveErrorMessage = errorMessage
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    saveErrorMessage = nil
                    isEditing = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private static func sanitizedItemName(_ rawName: String, quantity: Int) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return rawName }

        let withoutTrailingCurrency = trimmedName.replacingOccurrences(
            of: #"\s*\$$"#,
            with: "",
            options: .regularExpression
        )

        let quantityPrefix = "\(quantity) "
        if withoutTrailingCurrency.hasPrefix(quantityPrefix) {
            return String(withoutTrailingCurrency.dropFirst(quantityPrefix.count))
        }

        return withoutTrailingCurrency
    }
}
