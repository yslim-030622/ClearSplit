import SwiftUI

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var itemName = ""
    @State private var unitPriceText = ""
    @State private var quantity = 1
    @State private var selectedParticipants: Set<UUID> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardAlert = false
    @State private var formErrors: [String: String] = [:]
    @State private var loadedSession: ShoppingSession?

    @FocusState private var focusedField: Field?

    enum Field {
        case name, price
    }

    let appState: AppState
    let sessionId: UUID
    let groupId: UUID
    let onAdded: (ShoppingSession) -> Void

    var participants: [ShoppingSessionParticipant] {
        loadedSession?.participants ?? []
    }

    var unitPrice: Double {
        Double(unitPriceText) ?? 0
    }

    var itemTotal: Double {
        unitPrice * Double(quantity)
    }

    var isDirty: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty ||
        !unitPriceText.isEmpty ||
        quantity != 1 ||
        !selectedParticipants.isEmpty
    }

    var isValid: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty &&
        unitPrice > 0 &&
        quantity >= 1 &&
        !selectedParticipants.isEmpty &&
        formErrors.isEmpty
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Item Details Card
                    VStack(alignment: .leading, spacing: 20) {
                        AddItemNameField(
                            itemName: $itemName,
                            focusedField: $focusedField,
                            formErrors: formErrors,
                            onValidationChange: validateField
                        )

                        AddItemPriceQuantitySection(
                            unitPriceText: $unitPriceText,
                            quantity: $quantity,
                            focusedField: $focusedField,
                            formErrors: formErrors,
                            itemTotal: itemTotal,
                            onValidationChange: validateField
                        )
                    }
                    .padding(20)
                    .sectionStyle()

                    // Participants Selection
                    AddItemParticipantsSection(
                        participants: participants,
                        selectedParticipants: $selectedParticipants,
                        formErrors: formErrors
                    )

                    // Error Message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(ClearSplitTheme.Typography.subheadline)
                            .foregroundColor(.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.dangerSurface)
                            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                    }

                    Spacer()
                }
                .padding(16)
            }
            .background { AppBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add Item")
                        .font(ClearSplitTheme.Typography.sectionTitle)
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if isDirty {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Text("Cancel")
                            .foregroundColor(.brandPrimary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await saveItem() } }) {
                        Text("Add")
                            .font(ClearSplitTheme.Typography.bodyStrong)
                            .foregroundColor(isValid ? .brandPrimary : .textMuted)
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Keep Editing", role: .cancel) { }
                Button("Discard", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("You have unsaved changes.")
            }
        }
        .task {
            await loadSession()
        }
    }

    private func loadSession() async {
        do {
            loadedSession = try await appState.shoppingService.getSession(sessionId: sessionId)

            if let session = loadedSession, !session.participants.isEmpty {
                if let firstParticipant = session.participants.first {
                    selectedParticipants.insert(firstParticipant.membershipId)
                }
            }
        } catch {
            errorMessage = "Failed to load session details."
        }
    }

    private func validateField(_ field: String, _ value: String) {
        formErrors.removeValue(forKey: field)

        switch field {
        case "name":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                formErrors["name"] = "Item name is required"
            } else if trimmed.count > 100 {
                formErrors["name"] = "Name must be less than 100 characters"
            }
        case "unitPrice":
            if let price = Double(value) {
                if price <= 0 {
                    formErrors["unitPrice"] = "Price must be greater than $0"
                } else if price > 999999.99 {
                    formErrors["unitPrice"] = "Price exceeds maximum"
                }
            } else if !value.isEmpty {
                formErrors["unitPrice"] = "Enter a valid price"
            }
        default:
            break
        }
    }

    private func validateForm() -> Bool {
        formErrors.removeAll()

        let trimmedName = itemName.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty {
            formErrors["name"] = "Item name is required"
        } else if trimmedName.count > 100 {
            formErrors["name"] = "Name must be less than 100 characters"
        }

        if unitPrice <= 0 {
            formErrors["unitPrice"] = "Price must be greater than $0"
        } else if unitPrice > 999999.99 {
            formErrors["unitPrice"] = "Price exceeds maximum"
        }

        if quantity < 1 {
            formErrors["quantity"] = "Quantity must be at least 1"
        } else if quantity > 999 {
            formErrors["quantity"] = "Quantity exceeds maximum"
        }

        if selectedParticipants.isEmpty {
            formErrors["participants"] = "Select at least one person to split with"
        }

        return formErrors.isEmpty
    }

    private func saveItem() async {
        guard validateForm() else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let totalCents = Int((itemTotal * 100).rounded())
            let unitPriceCents = Int((unitPrice * 100).rounded())

            let itemRequest = ShoppingItemCreate(
                name: itemName.trimmingCharacters(in: .whitespaces),
                quantity: quantity,
                unitPriceCents: unitPriceCents,
                totalCents: totalCents
            )

            let createdItem = try await appState.shoppingService.createItem(
                sessionId: sessionId,
                request: itemRequest
            )

            let sharersRequest = SharersSetRequest(membershipIds: Array(selectedParticipants))
            _ = try await appState.shoppingService.setSharers(
                itemId: createdItem.id,
                request: sharersRequest
            )

            let updated = try await appState.refreshShoppingSession(sessionId: sessionId, groupId: groupId)
            onAdded(updated)
            dismiss()
        } catch {
            errorMessage = "Failed to add item. Please try again."
        }
    }
}
