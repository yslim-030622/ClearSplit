import SwiftUI
import PhotosUI

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem?
    
    let appState: AppState
    
    init(appState: AppState, sessionId: UUID) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ShoppingSessionDetailViewModel(appState: appState, sessionId: sessionId))
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.session == nil {
                ProgressView()
            } else if let session = viewModel.session {
                List {
                    // Summary Section
                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(viewModel.formattedTotal)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // Participants Section
                    Section("Participants") {
                        if session.participants.isEmpty {
                            Text("No participants set")
                                .foregroundColor(.secondary)
                            
                            if viewModel.isPayer {
                                Button("Set Participants") {
                                    // TODO: Show participant selection
                                }
                            }
                        } else {
                            ForEach(session.participants) { participant in
                                Text("Membership: \(participant.membershipId.uuidString.prefix(8))...")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    // Receipts Section
                    Section("Receipts") {
                        if session.receipts.isEmpty {
                            Text("No receipts uploaded")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(session.receipts) { receipt in
                                HStack {
                                    Image(systemName: "doc.text.image")
                                    Text("Receipt")
                                    Spacer()
                                    Text(receipt.contentType)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if viewModel.isPayer {
                            PhotosPicker(
                                selection: $selectedImageItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("Upload Receipt", systemImage: "photo")
                            }
                            .disabled(viewModel.isUploadingReceipt)
                        }
                    }
                    
                    // Items Section
                    Section("Items") {
                        if session.items.isEmpty {
                            Text("No items added")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(session.items) { item in
                                ItemRow(item: item)
                            }
                        }
                        
                        if viewModel.isPayer {
                            Button(action: { showingAddItem = true }) {
                                Label("Add Item", systemImage: "plus.circle.fill")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(viewModel.session?.title ?? "Shopping Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingAddItem) {
            if let session = viewModel.session {
                AddItemSheet(
                    appState: appState,
                    sessionId: session.id,
                    groupId: session.groupId,
                    onAdded: { updated in
                        showingAddItem = false
                        viewModel.session = updated
                    }
                )
            }
        }
        .onChange(of: selectedImageItem) { oldValue, newValue in
            Task {
                if let item = newValue,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    _ = await viewModel.uploadReceipt(imageData: data)
                    selectedImageItem = nil
                }
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Upload Error", isPresented: .constant(viewModel.uploadError != nil)) {
            Button("OK") { viewModel.uploadError = nil }
        } message: {
            Text(viewModel.uploadError ?? "")
        }
    }
}

struct ItemRow: View {
    let item: ShoppingItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                    .font(.headline)
                
                Spacer()
                
                Text(item.formattedTotal)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack {
                Text("Qty \(item.quantity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let splits = item.splits, !splits.isEmpty {
                    Text("Split \(splits.count) ways")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let splits = item.splits, !splits.isEmpty {
                ForEach(splits) { split in
                    HStack {
                        Text("Member \(split.membershipId.uuidString.prefix(8))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(split.formattedShare)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
