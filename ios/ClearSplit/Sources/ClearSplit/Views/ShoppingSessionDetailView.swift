import SwiftUI
import Foundation

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingReceiptUpload = false
    @State private var showingExtractedItems = false
    @State private var uploadedReceiptId: UUID?
    @State private var pendingDeleteItem: ShoppingItem?
    @State private var pendingDeleteReceipt: ReceiptUpload?
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var appState: AppState

    private var currentUserId: UUID? {
        appState.user?.id
    }

    init(appState: AppState, sessionId: UUID) {
        _appState = ObservedObject(wrappedValue: appState)
        _viewModel = StateObject(wrappedValue: ShoppingSessionDetailViewModel(appState: appState, sessionId: sessionId))
    }

    var body: some View {
        SwiftUI.Group {
            if viewModel.isLoading && viewModel.session == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = viewModel.session {
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
                                participants: session.participants,
                                groupMemberships: appState.membershipsByGroupId[session.groupId] ?? [],
                                currentUserId: currentUserId
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

                            // Items Section
                            ItemsDetailCard(
                                items: session.items,
                                participants: session.participants,
                                groupMemberships: appState.membershipsByGroupId[session.groupId] ?? [],
                                currentUserId: currentUserId,
                                displayMode: .detailed,
                                onAddItem: {
                                    showingAddItem = true
                                },
                                onSaveItem: { item, request, membershipIds in
                                    do {
                                        _ = try await appState.updateShoppingItem(
                                            itemId: item.id,
                                            sessionId: session.id,
                                            groupId: session.groupId,
                                            request: request,
                                            membershipIds: membershipIds
                                        )
                                        await viewModel.load()
                                        return nil
                                    } catch AppStateError.invalidParticipants {
                                        return "Select at least one participant."
                                    } catch {
                                        return "Failed to update item. Please try again."
                                    }
                                },
                                onDeleteItem: { itemId in
                                    pendingDeleteItem = session.items.first(where: { $0.id == itemId })
                                },
                                onItemTap: { _ in }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
                .background(Color.pageBackground)
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
            if let groupId = viewModel.session?.groupId {
                _ = try? await appState.loadMembers(groupId: groupId)
            }
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
        .confirmationDialog(
            "Delete Item",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeleteItem = nil
            }
            Button("Delete", role: .destructive) {
                guard let item = pendingDeleteItem, let session = viewModel.session else { return }
                pendingDeleteItem = nil
                Task {
                    do {
                        try await appState.deleteShoppingItem(
                            itemId: item.id,
                            sessionId: session.id,
                            groupId: session.groupId
                        )
                        await viewModel.load()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } catch {
                        viewModel.errorMessage = "Failed to delete item. Please try again."
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }
        } message: {
            if let item = pendingDeleteItem {
                Text("Are you sure you want to delete \"\(item.name)\"?")
            }
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
