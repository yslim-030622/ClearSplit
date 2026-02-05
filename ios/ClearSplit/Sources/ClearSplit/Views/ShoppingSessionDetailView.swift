import SwiftUI
import Foundation

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingReceiptUpload = false
    @State private var pendingDeleteReceipt: ReceiptUpload?
    @State private var showDeleteConfirm = false
    @State private var groupMemberships: [Membership] = []
    @Environment(\.dismiss) private var dismiss
    
    let appState: AppState
    
    init(appState: AppState, sessionId: UUID) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ShoppingSessionDetailViewModel(appState: appState, sessionId: sessionId))
    }
    
    var body: some View {
        Group {
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
                                paidByMembershipId: session.paidByMembershipId,
                                groupMemberships: groupMemberships,
                                currentUserId: appState.user?.id
                            )
                            
                            // Content Area
                            VStack(spacing: 16) {
                                // Participants Card
                                ParticipantsDetailCard(
                                    participants: session.participants,
                                    groupMemberships: groupMemberships,
                                    currentUserId: appState.user?.id
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
                                    groupMemberships: groupMemberships,
                                    currentUserId: appState.user?.id,
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
                            showingReceiptUpload = false
                            // Reload session to get updated receipts
                            Task {
                                await viewModel.load()
                            }
                        },
                        onBack: {
                            showingReceiptUpload = false
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    if let session = viewModel.session {
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
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if let session = viewModel.session {
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
            if let session = viewModel.session {
                await loadGroupMemberships(groupId: session.groupId)
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
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
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
    
    private func loadGroupMemberships(groupId: UUID) async {
        do {
            groupMemberships = try await appState.groupsService.listMemberships(groupId: groupId)
        } catch {
            // Silently fail
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
        guard let currentUserId = appState.user?.id else { return false }
        guard let membership = groupMemberships.first(where: { $0.user?.id == currentUserId }) else {
            return false
        }
        return membership.id == session.paidByMembershipId
    }
}

// MARK: - Total Amount Hero Card

struct TotalAmountHeroCard: View {
    let totalCents: Int
    let paidByMembershipId: UUID
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text("Total Amount")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 8)
            
            // Amount
            Text(formatCurrency(cents: totalCents, currency: "USD"))
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            
            // Paid by
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(paidByText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue600, Color.blue700],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(24, corners: [.bottomLeft, .bottomRight])
    }
    
    private var paidByText: String {
        guard let currentUserId = currentUserId else {
            return "Paid by Unknown"
        }
        
        guard let membership = groupMemberships.first(where: { $0.id == paidByMembershipId }),
              let user = membership.user else {
            return "Paid by Unknown"
        }
        
        if user.id == currentUserId {
            return "Paid by You"
        }
        
        return "Paid by \(user.firstName) \(user.lastName)"
    }
}

// MARK: - Participants Detail Card

struct ParticipantsDetailCard: View {
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)
                    
                    Text("Participants")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                
                Spacer()
                
                // Count Badge
                Text("\(participants.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue700)
                    .frame(width: 24, height: 24)
                    .background(Color.blue50)
                    .clipShape(Circle())
            }
            
            // Participants List
            HStack(spacing: 16) {
                ForEach(participants) { participant in
                    ParticipantAvatarView(
                        participant: participant,
                        membership: groupMemberships.first(where: { $0.id == participant.membershipId }),
                        currentUserId: currentUserId
                    )
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Participant Avatar View

struct ParticipantAvatarView: View {
    let participant: ShoppingSessionParticipant
    let membership: Membership?
    let currentUserId: UUID?
    
    var body: some View {
        VStack(spacing: 6) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 40, height: 40)
                
                Text(displayInitial)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Name
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray700)
        }
    }
    
    private var displayName: String {
        if let membership = membership,
           let user = membership.user {
            if user.id == currentUserId {
                return "You"
            }
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
    
    private var displayInitial: String {
        if let membership = membership,
           let user = membership.user {
            return String(user.firstName.prefix(1)).uppercased()
        }
        return String(participant.membershipId.uuidString.prefix(1)).uppercased()
    }
    
    private var avatarGradient: LinearGradient {
        let colors = [
            [Color(hex: "60A5FA"), Color(hex: "2563EB")], // Blue
            [Color(hex: "38BDF8"), Color(hex: "0284C7")], // Sky
            [Color(hex: "3B82F6"), Color(hex: "1D4ED8")], // Blue variant
            [Color(hex: "6366F1"), Color(hex: "4F46E5")], // Indigo
            [Color(hex: "8B5CF6"), Color(hex: "7C3AED")], // Purple
            [Color(hex: "EC4899"), Color(hex: "DB2777")], // Pink
            [Color(hex: "10B981"), Color(hex: "059669")], // Green
            [Color(hex: "F59E0B"), Color(hex: "D97706")]  // Amber
        ]
        
        let hash = participant.membershipId.uuidString.hashValue
        let index = abs(hash) % colors.count
        let colorPair = colors[index]
        
        return LinearGradient(
            colors: colorPair,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Receipts Detail Card

struct ReceiptsDetailCard: View {
    let receipts: [ReceiptUpload]
    let appState: AppState
    let canDelete: Bool
    let onDeleteTap: (ReceiptUpload) -> Void
    let onUploadTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)
                    
                    Text("Receipts")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }
                
                Spacer()
                
                // Camera Button in card (backup to toolbar button)
                Button(action: onUploadTap) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue600)
                        .frame(width: 44, height: 44)
                        .background(Color.blue50)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Receipt Content
            if receipts.isEmpty {
                // Empty State
                Button(action: {
                    onUploadTap()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray100)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                    .foregroundColor(.gray300)
                            )
                        
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray400)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Receipt Thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(receipts) { receipt in
                            ReceiptThumbnailView(
                                receipt: receipt,
                                appState: appState,
                                canDelete: canDelete,
                                onDeleteTap: onDeleteTap
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Receipt Thumbnail View

struct ReceiptThumbnailView: View {
    let receipt: ReceiptUpload
    let appState: AppState
    let canDelete: Bool
    let onDeleteTap: (ReceiptUpload) -> Void
    
    @State private var imageURL: URL?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        contentView
            .task {
                await loadImageURL()
            }
            .contextMenu {
                if canDelete {
                    Button(role: .destructive) {
                        onDeleteTap(receipt)
                    } label: {
                        Label("Delete Receipt", systemImage: "trash")
                    }
                }
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    loadingView
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray200, lineWidth: 1)
                        )
                case .failure(let error):
                    print("[ReceiptThumbnailView] ❌ AsyncImage failed to load image")
                    print("[ReceiptThumbnailView] URL: \(url.absoluteString)")
                    print("[ReceiptThumbnailView] Error: \(error.localizedDescription)")
                    if let urlError = error as? URLError {
                        print("[ReceiptThumbnailView] URLError code: \(urlError.code.rawValue)")
                        print("[ReceiptThumbnailView] URLError description: \(urlError.localizedDescription)")
                    }
                    errorView
                @unknown default:
                    loadingView
                }
            }
            .onAppear {
                // Test URL reachability when view appears
                testURLReachability(url: url)
            }
        } else if isLoading {
            loadingView
        } else {
            errorView
        }
    }
    
    private var loadingView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray200)
            .frame(width: 80, height: 80)
            .overlay(
                ProgressView()
                    .scaleEffect(0.8)
            )
    }
    
    private var errorView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray200)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.gray400)
            )
    }
    
    private func loadImageURL() async {
        // Avoid refetching if we already have a URL
        guard imageURL == nil && isLoading else {
            print("[ReceiptThumbnailView] Skipping load - already have URL or not loading. receiptId=\(receipt.id), hasURL=\(imageURL != nil), isLoading=\(isLoading)")
            return
        }
        
        print("[ReceiptThumbnailView] Starting to load download URL for receipt: \(receipt.id)")
        
        do {
            let urlString = try await appState.getReceiptDownloadURL(receiptUploadId: receipt.id)
            print("[ReceiptThumbnailView] Received URL string: \(urlString)")
            print("[ReceiptThumbnailView] URL scheme: \(URL(string: urlString)?.scheme ?? "nil")")
            print("[ReceiptThumbnailView] URL host: \(URL(string: urlString)?.host ?? "nil")")
            
            if let url = URL(string: urlString) {
                print("[ReceiptThumbnailView] Successfully created URL object: \(url)")
                
                // Test URL reachability immediately
                await testURLReachability(url: url)
                
                await MainActor.run {
                    self.imageURL = url
                    self.isLoading = false
                    print("[ReceiptThumbnailView] Set imageURL and cleared loading state")
                }
            } else {
                print("[ReceiptThumbnailView] ❌ Failed to create URL from string: '\(urlString)'")
                print("[ReceiptThumbnailView] URL string length: \(urlString.count)")
                print("[ReceiptThumbnailView] URL string contains percent encoding: \(urlString.contains("%"))")
                await MainActor.run {
                    self.loadError = true
                    self.isLoading = false
                }
            }
        } catch {
            print("[ReceiptThumbnailView] ❌ Failed to load image URL for receipt \(receipt.id)")
            print("[ReceiptThumbnailView] Error type: \(type(of: error))")
            print("[ReceiptThumbnailView] Error description: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                switch apiError {
                case .server(let status, let message):
                    print("[ReceiptThumbnailView] API Error - Status: \(status), Message: \(message ?? "nil")")
                case .unauthorized:
                    print("[ReceiptThumbnailView] API Error - Unauthorized (401)")
                case .decoding:
                    print("[ReceiptThumbnailView] API Error - Decoding failed")
                case .network(let underlyingError):
                    print("[ReceiptThumbnailView] API Error - Network error: \(underlyingError)")
                }
            }
            await MainActor.run {
                self.loadError = true
                self.isLoading = false
            }
        }
    }
    
    private func testURLReachability(url: URL) async {
        print("[ReceiptThumbnailView] 🔍 Testing URL reachability: \(url.absoluteString)")
        print("[ReceiptThumbnailView] URL scheme: \(url.scheme ?? "nil")")
        print("[ReceiptThumbnailView] URL host: \(url.host ?? "nil")")
        print("[ReceiptThumbnailView] URL path: \(url.path)")
        
        // Check for ATS restrictions
        if url.scheme == "http" {
            print("[ReceiptThumbnailView] ⚠️ WARNING: URL uses HTTP (not HTTPS) - ATS may block this!")
            print("[ReceiptThumbnailView] ⚠️ Need to add ATS exception in Info.plist for host: \(url.host ?? "unknown")")
        }
        
        // Manual URL fetch test
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            
            print("[ReceiptThumbnailView] 📡 Starting manual URL fetch test...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("[ReceiptThumbnailView] ✅ Manual fetch succeeded!")
                print("[ReceiptThumbnailView] HTTP Status: \(httpResponse.statusCode)")
                print("[ReceiptThumbnailView] Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                print("[ReceiptThumbnailView] Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "nil")")
                print("[ReceiptThumbnailView] Data size: \(data.count) bytes")
                
                if httpResponse.statusCode == 200 {
                    print("[ReceiptThumbnailView] ✅ URL is reachable and returns 200 OK")
                    // Check if it's actually an image
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        print("[ReceiptThumbnailView] Content-Type: \(contentType)")
                        if contentType.hasPrefix("image/") {
                            print("[ReceiptThumbnailView] ✅ Response is an image")
                        } else {
                            print("[ReceiptThumbnailView] ⚠️ Response is not an image: \(contentType)")
                        }
                    }
                } else {
                    print("[ReceiptThumbnailView] ❌ URL returned non-200 status: \(httpResponse.statusCode)")
                    if let responseBody = String(data: data, encoding: .utf8) {
                        print("[ReceiptThumbnailView] Response body: \(responseBody.prefix(200))")
                    }
                }
            } else {
                print("[ReceiptThumbnailView] ⚠️ Response is not HTTPURLResponse")
            }
        } catch {
            print("[ReceiptThumbnailView] ❌ Manual URL fetch failed!")
            print("[ReceiptThumbnailView] Error: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("[ReceiptThumbnailView] URLError code: \(urlError.code.rawValue)")
                print("[ReceiptThumbnailView] URLError description: \(urlError.localizedDescription)")
                
                switch urlError.code {
                case .notConnectedToInternet:
                    print("[ReceiptThumbnailView] ❌ Network connection issue")
                case .timedOut:
                    print("[ReceiptThumbnailView] ❌ Request timed out")
                case .cannotFindHost:
                    print("[ReceiptThumbnailView] ❌ Cannot find host - DNS issue")
                case .cannotConnectToHost:
                    print("[ReceiptThumbnailView] ❌ Cannot connect to host")
                case .networkConnectionLost:
                    print("[ReceiptThumbnailView] ❌ Network connection lost")
                case .appTransportSecurityRequiresSecureConnection:
                    print("[ReceiptThumbnailView] ❌ ATS blocked HTTP connection - need HTTPS or ATS exception")
                default:
                    print("[ReceiptThumbnailView] ❌ Other URLError: \(urlError)")
                }
            }
        }
    }
}

// MARK: - Items Detail Card

struct ItemsDetailCard: View {
    let items: [ShoppingItem]
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onItemTap: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Items")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
                
                Spacer()
                
                // Count Badge
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray700)
                    .frame(width: 24, height: 24)
                    .background(Color.gray100)
                    .clipShape(Circle())
            }
            
            // Items List
            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    ForEach(items) { item in
                        ItemDetailRow(
                            item: item,
                            participants: participants,
                            groupMemberships: groupMemberships,
                            currentUserId: currentUserId,
                            onTap: {
                                onItemTap(item.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Item Detail Row

struct ItemDetailRow: View {
    let item: ShoppingItem
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Row 1: Name and Total
                HStack {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                    
                    Spacer()
                    
                    Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.gray900)
                }
                
                // Row 2: Unit Price × Quantity
                if let unitPriceCents = item.unitPriceCents {
                    Text("\(formatCurrency(cents: unitPriceCents, currency: "USD")) × \(item.quantity)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray500)
                }
                
                // Row 3: Shared by
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared by:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray600)
                    
                    // Participant Badges
                    HStack(spacing: 8) {
                        ForEach(sharedByMemberships) { membership in
                            ParticipantBadge(
                                membership: membership,
                                currentUserId: currentUserId
                            )
                        }
                    }
                }
                
                // Row 4: Your Share
                HStack {
                    Text("Your share:")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray600)
                    
                    Spacer()
                    
                    Text(formatCurrency(cents: userShareCents, currency: "USD"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray50)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray200, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var sharedByMemberships: [Membership] {
        let membershipIds = item.splits.map { $0.membershipId }
        return groupMemberships.filter { membershipIds.contains($0.id) }
    }
    
    private var userShareCents: Int {
        guard let currentUserId = currentUserId else { return 0 }
        
        guard let currentMembership = groupMemberships.first(where: { $0.user?.id == currentUserId }) else {
            return 0
        }
        
        if let split = item.splits.first(where: { $0.membershipId == currentMembership.id }) {
            return split.shareCents
        }
        
        return 0
    }
}

// MARK: - Participant Badge

struct ParticipantBadge: View {
    let membership: Membership
    let currentUserId: UUID?
    
    var body: some View {
        Text(displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.blue700)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.blue50)
            .cornerRadius(14)
    }
    
    private var displayName: String {
        if let user = membership.user {
            if user.id == currentUserId {
                return "You"
            }
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
}

// MARK: - Add Item Fixed Button

struct AddItemFixedButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Add Item")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.blue600)
            .cornerRadius(26)
            .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
