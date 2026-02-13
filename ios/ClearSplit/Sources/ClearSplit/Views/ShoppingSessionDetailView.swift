import SwiftUI
import Foundation

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingReceiptUpload = false
    @State private var showingExtractedItems = false
    @State private var showingParticipantsEditor = false
    @State private var uploadedReceiptId: UUID?
    @State private var participantDraft: Set<UUID> = []
    @State private var participantSaveError: String?
    @State private var isParticipantsEditorLoadingMembers = false
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
                                currentUserId: currentUserId,
                                canEdit: true,
                                onEditTapped: {
                                    openParticipantsEditor(for: session)
                                }
                            )

                            // Receipts Card
                            ReceiptsDetailCard(
                                receipts: session.receipts,
                                appState: appState,
                                canUpload: canUploadReceipt(session: session),
                                editableReceiptIds: Set(
                                    session.receipts
                                        .filter { canEditReceipt($0, in: session) }
                                        .map(\.id)
                                ),
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
                    if canUploadReceipt(session: session) {
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
        .sheet(isPresented: $showingParticipantsEditor) {
            if let session = viewModel.session {
                let groupMembers = appState.membershipsByGroupId[session.groupId] ?? []
                NavigationStack {
                    VStack(spacing: 0) {
                        if let participantSaveError {
                            Text(participantSaveError)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red600)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }

                        if isParticipantsEditorLoadingMembers && groupMembers.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading group members...")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.gray500)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if groupMembers.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundColor(.gray500)
                                Text("No group members available.")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.gray700)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List {
                                Section {
                                    ForEach(groupMembers) { membership in
                                        Button {
                                            toggleParticipantSelection(
                                                membershipId: membership.id,
                                                payerMembershipId: session.paidByMembershipId
                                            )
                                        } label: {
                                            HStack(spacing: 12) {
                                                Text(displayName(for: membership))
                                                    .font(.system(size: 16, weight: .regular))
                                                    .foregroundColor(.gray900)

                                                Spacer()

                                                if membership.id == session.paidByMembershipId {
                                                    Text("Payer")
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.blue700)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.blue50)
                                                        .clipShape(Capsule())
                                                }

                                                Image(systemName: participantDraft.contains(membership.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 20, weight: .regular))
                                                    .foregroundColor(participantDraft.contains(membership.id) ? .blue600 : .gray400)
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                } footer: {
                                    Text("Only group members can be session participants. The payer must remain selected.")
                                        .font(.system(size: 12, weight: .regular))
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    }
                    .navigationTitle("Set Participants")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingParticipantsEditor = false
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                participantSaveError = nil
                                Task {
                                    let saved = await viewModel.setParticipants(Array(participantDraft))
                                    if saved {
                                        showingParticipantsEditor = false
                                    } else {
                                        participantSaveError = viewModel.errorMessage ?? "Failed to set participants."
                                        viewModel.errorMessage = nil
                                    }
                                }
                            }
                            .disabled(
                                participantDraft.isEmpty ||
                                !participantDraft.contains(session.paidByMembershipId) ||
                                viewModel.isLoading
                            )
                        }
                    }
                }
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
                                viewModel.errorMessage = "You don't have permission to edit this receipt. Only the uploader can edit or delete it."
                            case .server(let status, let message):
                                if status == 403 {
                                    viewModel.errorMessage = "You don't have permission to edit this receipt. Only the uploader can edit or delete it."
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

    private func currentMembershipId(for groupId: UUID) -> UUID? {
        guard let userId = appState.user?.id else { return nil }
        return appState.membershipsByGroupId[groupId]?.first(where: { $0.userId == userId })?.id
    }

    private func canUploadReceipt(session: ShoppingSession) -> Bool {
        guard session.receipts.isEmpty else { return false }
        guard let membershipId = currentMembershipId(for: session.groupId) else { return false }
        return session.participants.contains(where: { $0.membershipId == membershipId })
    }

    private func canEditReceipt(_ receipt: ReceiptUpload, in session: ShoppingSession) -> Bool {
        guard let membershipId = currentMembershipId(for: session.groupId) else { return false }
        let uploaderMembershipId = receipt.uploadedByMembershipId ?? session.paidByMembershipId
        return membershipId == uploaderMembershipId
    }

    private func openParticipantsEditor(for session: ShoppingSession) {
        participantSaveError = nil
        let currentSelection = Set(session.participants.map(\.membershipId))
        if currentSelection.isEmpty {
            participantDraft = [session.paidByMembershipId]
        } else {
            participantDraft = currentSelection
            participantDraft.insert(session.paidByMembershipId)
        }

        if appState.membershipsByGroupId[session.groupId] == nil {
            isParticipantsEditorLoadingMembers = true
            Task {
                defer { isParticipantsEditorLoadingMembers = false }
                try? await appState.loadMembers(groupId: session.groupId)
            }
        } else {
            isParticipantsEditorLoadingMembers = false
        }

        showingParticipantsEditor = true
    }

    private func toggleParticipantSelection(membershipId: UUID, payerMembershipId: UUID) {
        if membershipId == payerMembershipId {
            participantDraft.insert(membershipId)
            return
        }
        if participantDraft.contains(membershipId) {
            participantDraft.remove(membershipId)
        } else {
            participantDraft.insert(membershipId)
        }
    }

    private func displayName(for membership: Membership) -> String {
        if membership.userId == currentUserId {
            return "You"
        }

        if let user = membership.user {
            let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty {
                return fullName
            }
            return user.email
        }

        return membership.displayName
    }
}
