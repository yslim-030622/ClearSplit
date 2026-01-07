import SwiftUI

struct CreateShoppingSessionView: View {
    @StateObject private var viewModel: CreateShoppingSessionViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onCreated: () -> Void
    
    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID, onCreated: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: CreateShoppingSessionViewModel(
            appState: appState,
            groupId: groupId,
            paidByMembershipId: paidByMembershipId
        ))
        self.onCreated = onCreated
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title (e.g., Costco)", text: $viewModel.title)
                        .textInputAutocapitalization(.words)
                    
                    Toggle("Include Date", isOn: $viewModel.useDate)
                    
                    if viewModel.useDate {
                        DatePicker("Date", selection: $viewModel.shoppingDate, displayedComponents: .date)
                    }
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Shopping Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.createSession() != nil {
                                onCreated()
                            }
                        }
                    }
                    .disabled(!viewModel.canCreate || viewModel.isCreating)
                }
            }
            .disabled(viewModel.isCreating)
        }
    }
}

