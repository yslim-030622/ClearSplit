import SwiftUI

struct AddItemView: View {
    @StateObject private var viewModel: AddItemViewModel
    @Environment(\.dismiss) private var dismiss
    
    let onAdded: () -> Void
    
    init(appState: AppState, sessionId: UUID, participants: [ShoppingSessionParticipant], onAdded: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: AddItemViewModel(
            appState: appState,
            sessionId: sessionId,
            participants: participants
        ))
        self.onAdded = onAdded
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Item Details Section
                Section("Item Details") {
                    TextField("Name", text: $viewModel.name)
                        .textInputAutocapitalization(.words)
                    
                    Toggle("Use Unit Price", isOn: $viewModel.useUnitPrice)
                    
                    if viewModel.useUnitPrice {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            TextField("1", text: $viewModel.quantity)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        
                        HStack {
                            Text("Unit Price")
                            Spacer()
                            TextField("0.00", text: $viewModel.unitPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    } else {
                        HStack {
                            Text("Total Price")
                            Spacer()
                            TextField("0.00", text: $viewModel.totalPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                }
                
                // Sharers Section
                Section {
                    ForEach(viewModel.participants, id: \.membershipId) { participant in
                        Button(action: { viewModel.toggleSharer(participant.membershipId) }) {
                            HStack {
                                Text("Member \(participant.membershipId.uuidString.prefix(8))...")
                                Spacer()
                                if viewModel.selectedSharers.contains(participant.membershipId) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    
                    Button("Select All") {
                        viewModel.selectAllSharers()
                    }
                } header: {
                    Text("Who shares this item?")
                } footer: {
                    if !viewModel.selectedSharers.isEmpty {
                        Text("\(viewModel.selectedSharers.count) sharers selected")
                    }
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                if let sharingError = viewModel.sharingError {
                    Section {
                        Text(sharingError)
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
                    Button("Add") {
                        Task {
                            if let itemId = await viewModel.createItem() {
                                if await viewModel.setSharers(itemId: itemId) {
                                    onAdded()
                                }
                            }
                        }
                    }
                    .disabled(!viewModel.canCreateItem || !viewModel.canSetSharers || viewModel.isCreating || viewModel.isSettingSharers)
                }
            }
            .disabled(viewModel.isCreating || viewModel.isSettingSharers)
        }
    }
}

