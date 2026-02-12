import SwiftUI
import Foundation

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingReceiptUpload = false
    @State private var showingExtractedItems = false
    @State private var uploadedReceiptId: UUID?
    @State private var pendingDeleteReceipt: ReceiptUpload?
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    let appState: AppState

    init(appState: AppState, sessionId: UUID) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ShoppingSessionDetailViewModel(appState: appState, sessionId: sessionId))
    }

    var body: some View {
        SwiftUI.Group {
            if viewModel.isLoading && viewModel.session == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = viewModel.session {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Blue Gradient Hero Card
                            TotalAmountHeroCard(
                                totalCents: session.totalCents,
                                paidByMembershipId: session.paidByMembershipId
                            )

                            // Content Area
                            VStack(spacing: 16) {
                                // Participants Card
                                ParticipantsDetailCard(
                                    participants: session.participants
                                )

                                // Receipts Card
                                ReceiptsDetailCard(
                                    receipts: session.receipts,
                                    appState: appState,
                                    canDelete: canDeleteReceipts(session: session),
                                    onDeleteTap: { receipt in
                                        pendingDeleteReceipt = receipt
                                        showDeleteConfirm = true
                                    },
                                    onUploadTap: {
                                        showingReceiptUpload = true
                                    }
                                )

                                // Items Card
                                ItemsDetailCard(
                                    items: session.items,
                                    participants: session.participants,
                                    onItemTap: { itemId in
                                        // TODO: Navigate to edit item
                                    }
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 100) // Space for fixed button
                        }
                    }
                    .background(Color.white)

                    // Fixed Add Item Button
                    AddItemFixedButton {
                        showingAddItem = true
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .sheet(isPresented: $showingReceiptUpload) {
                    ReceiptUploadView(
                        sessionId: session.id,
                        appState: appState,
                        onUploadComplete: { receipt in
                            // Store receipt ID
                            uploadedReceiptId = receipt.id
                            showingReceiptUpload = false

                            // Delay showing OCR review to allow upload sheet to dismiss properly
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                showingExtractedItems = true
                            }
                        },
                        onBack: {
                            showingReceiptUpload = false
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showingExtractedItems) {
                    if let receiptId = uploadedReceiptId {
                        ExtractedItemsReviewView(
                            sessionId: session.id,
                            groupId: session.groupId,
                            receiptUploadId: receiptId,
                            participants: session.participants,
                            appState: appState
                        )
                    }
                }
                .onChange(of: showingExtractedItems) { isShowing in
                    if !isShowing {
                        // When ExtractedItemsReviewView is dismissed, reload session
                        Task {
                            await viewModel.load()
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Session Not Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let session = viewModel.session {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(session.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.gray900)

                        if let dateString = session.shoppingDate,
                           let date = parseDate(dateString) {
                            Text(formatDate(date))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.gray500)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingReceiptUpload = true
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.blue600)
                    }
                }
            }
        }
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
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Delete receipt?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                guard let receipt = pendingDeleteReceipt else { return }
                Task {
                    do {
                        try await appState.deleteReceipt(receiptUploadId: receipt.id)
                        await viewModel.load()
                    } catch {
                        // Provide more specific error messages
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .unauthorized:
                                viewModel.errorMessage = "You don't have permission to delete this receipt. Only the payer can delete receipts."
                            case .server(let status, let message):
                                if status == 403 {
                                    viewModel.errorMessage = "You don't have permission to delete this receipt. Only the payer can delete receipts."
                                } else {
                                    viewModel.errorMessage = message ?? "Failed to delete receipt. Please try again."
                                }
                            case .network(let underlyingError):
                                viewModel.errorMessage = "Network error: \(underlyingError.localizedDescription). Please check your connection and try again."
                            default:
                                viewModel.errorMessage = "Failed to delete receipt. Please try again."
                            }
                        } else {
                            viewModel.errorMessage = "Failed to delete receipt: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently remove the receipt.")
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func canDeleteReceipts(session: ShoppingSession) -> Bool {
        // TODO: Implement permission check for receipt deletion
        return true
    }
}
