import SwiftUI

struct ShoppingSessionDetailView: View {
    @StateObject private var viewModel: ShoppingSessionDetailViewModel
    @State private var showingAddItem = false
    @State private var showingReceiptUpload = false
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
                
                // Camera Button
                Button(action: onUploadTap) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue600)
                        .frame(width: 44, height: 44)
                }
            }
            
            // Receipt Content
            if receipts.isEmpty {
                // Empty State
                Button(action: onUploadTap) {
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
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Receipt Thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(receipts) { receipt in
                            // TODO: Display receipt thumbnails
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray200)
                                .frame(width: 80, height: 80)
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
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
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
