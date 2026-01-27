import SwiftUI

struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var priceText = ""
    @State private var quantity = 1
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let appState: AppState
    let sessionId: UUID
    let groupId: UUID
    let onAdded: (ShoppingSession) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var priceDouble: Double? {
        Double(priceText.replacingOccurrences(of: ",", with: ""))
    }

    private var totalDisplay: String {
        guard let price = priceDouble, price > 0 else {
            return "$0.00"
        }
        let total = price * Double(quantity)
        return String(format: "$%.2f", total)
    }

    private var canSubmit: Bool {
        guard !trimmedName.isEmpty, let price = priceDouble else { return false }
        return price > 0 && quantity >= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }

                    Stepper(value: $quantity, in: 1...99) {
                        Text("Quantity: \(quantity)")
                    }
                }

                Section("Total") {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(totalDisplay)
                            .fontWeight(.semibold)
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
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
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task { await submit() }
                        }
                        .disabled(!canSubmit)
                    }
                }
            }
            .disabled(isSubmitting)
        }
    }

    private func submit() async {
        guard let price = priceDouble else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let updated = try await appState.addItemToSession(
                sessionId: sessionId,
                groupId: groupId,
                name: trimmedName,
                priceDouble: price,
                quantity: quantity
            )
            onAdded(updated)
            dismiss()
        } catch {
            errorMessage = "Unable to add item. Please check the details and try again."
        }
    }
}
