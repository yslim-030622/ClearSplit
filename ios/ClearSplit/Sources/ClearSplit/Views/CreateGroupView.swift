import SwiftUI

struct CreateGroupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var currency = "USD"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let supportedCurrencies = ["USD", "KRW", "JPY", "EUR", "GBP"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name", text: $groupName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Picker("Currency", selection: $currency) {
                        ForEach(supportedCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createGroup() }
                    }
                    .disabled(!canCreate || isSubmitting)
                }
            }
            .disabled(isSubmitting)
        }
    }

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createGroup() async {
        guard canCreate else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await appState.createGroup(
                name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                currency: currency
            )
            dismiss()
        } catch {
            errorMessage = "Failed to create group. Please try again."
        }
    }
}
