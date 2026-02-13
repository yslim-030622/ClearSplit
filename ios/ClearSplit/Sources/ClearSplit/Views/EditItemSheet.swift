import SwiftUI

struct EditItemSheet: View {
    let appState: AppState
    let sessionId: UUID
    let groupId: UUID
    let item: ShoppingItem
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var unitPriceText: String
    @State private var quantity: Int
    @State private var selectedMembershipIds: Set<UUID>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        appState: AppState,
        sessionId: UUID,
        groupId: UUID,
        item: ShoppingItem,
        participants: [ShoppingSessionParticipant],
        groupMemberships: [Membership],
        currentUserId: UUID?,
        onSaved: @escaping () -> Void
    ) {
        self.appState = appState
        self.sessionId = sessionId
        self.groupId = groupId
        self.item = item
        self.participants = participants
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
        self.onSaved = onSaved

        let fallbackUnitPriceCents: Int
        if let unitPriceCents = item.unitPriceCents {
            fallbackUnitPriceCents = unitPriceCents
        } else if item.quantity > 0 {
            fallbackUnitPriceCents = Int((Double(item.totalCents) / Double(item.quantity)).rounded())
        } else {
            fallbackUnitPriceCents = item.totalCents
        }

        _name = State(initialValue: item.name)
        _unitPriceText = State(initialValue: String(format: "%.2f", Double(fallbackUnitPriceCents) / 100.0))
        _quantity = State(initialValue: max(item.quantity, 1))

        let initialMembershipIds = Set(item.splits.map { $0.membershipId })
        if initialMembershipIds.isEmpty {
            _selectedMembershipIds = State(initialValue: Set(participants.map { $0.membershipId }))
        } else {
            _selectedMembershipIds = State(initialValue: initialMembershipIds)
        }
    }

    private var unitPrice: Double {
        Double(unitPriceText) ?? 0
    }

    private var totalAmount: Double {
        unitPrice * Double(quantity)
    }

    private var perPersonAmount: Double {
        guard !selectedMembershipIds.isEmpty else { return 0 }
        return totalAmount / Double(selectedMembershipIds.count)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        unitPrice > 0 &&
        quantity > 0 &&
        !selectedMembershipIds.isEmpty &&
        !isSaving
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
                            .foregroundColor(.gray600)
                        TextField("0.00", text: $unitPriceText)
                            .keyboardType(.decimalPad)
                    }

                    Stepper(value: $quantity, in: 1...999) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(quantity)")
                                .foregroundColor(.gray600)
                        }
                    }
                }

                Section("Shared With") {
                    if participants.isEmpty {
                        Text("No participants available")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray500)
                    } else {
                        ForEach(participants, id: \.membershipId) { participant in
                            Button(action: {
                                toggleMembership(participant.membershipId)
                            }) {
                                HStack {
                                    Text(displayName(for: participant.membershipId))
                                        .foregroundColor(.gray900)
                                    Spacer()
                                    if selectedMembershipIds.contains(participant.membershipId) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue500)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Total")
                            .foregroundColor(.gray600)
                        Spacer()
                        Text(String(format: "$%.2f", totalAmount))
                            .font(.system(size: 17, weight: .semibold))
                    }

                    if !selectedMembershipIds.isEmpty {
                        HStack {
                            Text("Per person")
                                .foregroundColor(.gray600)
                            Spacer()
                            Text(String(format: "$%.2f", perPersonAmount))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.blue500)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.red600)
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveItem() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
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

    private func displayName(for membershipId: UUID) -> String {
        let currentMembershipId = groupMemberships.first(where: { $0.user?.id == currentUserId })?.id
        if membershipId == currentMembershipId {
            return "You"
        }

        if let membership = groupMemberships.first(where: { $0.id == membershipId }),
           let user = membership.user {
            let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
            return fullName.isEmpty ? user.displayName : fullName
        }

        return "Member \(membershipId.uuidString.prefix(4).uppercased())"
    }

    @MainActor
    private func saveItem() async {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitPriceCents = Int((unitPrice * 100).rounded())
        let totalCents = Int((unitPrice * Double(quantity) * 100).rounded())

        let request = ShoppingItemCreate(
            name: trimmedName,
            quantity: quantity,
            unitPriceCents: unitPriceCents,
            totalCents: totalCents
        )

        do {
            _ = try await appState.updateShoppingItem(
                itemId: item.id,
                sessionId: sessionId,
                groupId: groupId,
                request: request,
                membershipIds: Array(selectedMembershipIds)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSaved()
            dismiss()
        } catch AppStateError.invalidParticipants {
            errorMessage = "Select at least one participant."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } catch {
            errorMessage = "Failed to update item. Please try again."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
