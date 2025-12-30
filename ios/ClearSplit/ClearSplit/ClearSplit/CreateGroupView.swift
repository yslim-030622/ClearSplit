//
//  CreateGroupView.swift
//  ClearSplit
//
//  Modal sheet for creating a new group
//

import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: GroupsViewModel
    
    @State private var groupName: String = ""
    @State private var selectedCurrency: String = "USD"
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    let currencies = ["USD", "KRW", "EUR", "GBP", "JPY", "CNY"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group Details")) {
                    TextField("Group Name", text: $groupName)
                        .textInputAutocapitalization(.words)
                        .disabled(isCreating)
                    
                    Picker("Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .disabled(isCreating)
                }
                
                Section {
                    Button {
                        Task { await createGroup() }
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text("Create Group")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(groupName.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func createGroup() async {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Group name is required"
            showError = true
            return
        }
        
        isCreating = true
        
        do {
            #if DEBUG
            print("🔄 Creating group: \(trimmedName) with currency: \(selectedCurrency)")
            #endif
            
            try await viewModel.createGroup(name: trimmedName, currency: selectedCurrency)
            
            #if DEBUG
            print("✅ Group created successfully, dismissing sheet")
            #endif
            
            // Success - dismiss sheet
            dismiss()
        } catch {
            // Error handling
            isCreating = false
            
            #if DEBUG
            print("❌ Failed to create group: \(error)")
            #endif
            
            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(let code, let message):
                    errorMessage = message ?? "Server error (\(code))"
                case .validationError(let message):
                    errorMessage = message
                case .networkError:
                    errorMessage = "Cannot connect to server"
                case .decodingError(let decError):
                    errorMessage = "Failed to process server response"
                    #if DEBUG
                    print("   Decoding error detail: \(decError)")
                    #endif
                default:
                    errorMessage = "Failed to create group"
                }
            } else {
                errorMessage = "Failed to create group"
            }
            showError = true
        }
    }
}

