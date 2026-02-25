import SwiftUI

@MainActor
struct GroupDetailView: View {
    @ObservedObject private var appState: AppState
    let group: Group
    
    @State private var isShowingHelp = false
    @State private var isAddMemberDialogOpen = false
    @State private var memberToRemove: Membership?
    @State private var isRemoveDialogOpen = false

    init(appState: AppState, group: Group) {
        _appState = ObservedObject(wrappedValue: appState)
        self.group = group
    }
    
    // MARK: - Derived Data
    
    private var members: [Membership] {
        appState.membershipsByGroupId[group.id] ?? []
    }
    
    private var shoppingSessions: [ShoppingSession] {
        appState.shoppingSessionsByGroupId[group.id] ?? []
    }
    
    private var totalSpentCents: Int {
        shoppingSessions.reduce(0) { $0 + $1.totalCents }
    }
    
    private var totalSpentDisplay: String {
        formatCurrency(cents: totalSpentCents, currency: group.currency)
    }
    
    private var currentUserId: UUID? {
        appState.user?.id
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    // Total Spent hero card
                    TotalSpentCard(
                        amountCents: totalSpentCents,
                        currency: group.currency,
                        subtitle: shoppingSessions.isEmpty
                            ? "No expenses yet"
                            : "Across all shopping trips"
                    )
                    .padding(.top, 16)
                    
                    // Members card
                    MembersCard(
                        title: "Members",
                        members: members,
                        currentUserId: currentUserId,
                        groupName: group.name,
                        onAddMember: { isAddMemberDialogOpen = true },
                        onRemoveMember: { member in
                            memberToRemove = member
                            isRemoveDialogOpen = true
                        }
                    )
                    
                    // Navigation cards
                    VStack(spacing: 16) {
                if let membershipId = group.userMembershipId {
                            NavigationCard(
                                iconName: "list.bullet.rectangle",
                                iconBackground: Color.blue50,
                                iconColor: Color.blue600,
                                title: "Shopping Sessions",
                                subtitle: "View and manage grocery trips"
                            ) {
                                ShoppingSessionsListView(
                                    appState: appState,
                                    groupId: group.id,
                                    paidByMembershipId: membershipId
                                )
                            }
                        } else {
                            // Disabled card when membership is missing
                            NavigationCardContent(
                                iconName: "list.bullet.rectangle",
                                iconBackground: Color.gray100,
                                iconColor: Color.gray400,
                                title: "Shopping Sessions",
                                subtitle: "Unavailable for this group"
                            )
                            .opacity(0.6)
                        }
                        
                        NavigationLink {
                            BalancesSettlementView(appState: appState, group: group)
                        } label: {
                            NavigationCardContent(
                                iconName: "dollarsign.circle",
                                iconBackground: Color.green.opacity(0.1),
                                iconColor: Color.green600,
                                title: "Balances & Settlement",
                                subtitle: "See who owes what"
                            )
                        }
                    }
                    
                    Spacer(minLength: 34)
                }
                .padding(.horizontal, 16)
            }
            
            // Floating help button
            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.gray800)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 54)
        }
        .navigationTitle(group.name.isEmpty ? "Unnamed Group" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // TODO: Implement group settings screen
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.gray600)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
        .sheet(isPresented: $isShowingHelp) {
            GroupHelpSheet()
        }
        .sheet(isPresented: $isAddMemberDialogOpen) {
            AddMemberDialog(
                groupName: group.name,
                groupId: group.id,
                members: members,
                appState: appState,
                onDismiss: {
                    isAddMemberDialogOpen = false
                    Task {
                        await refreshData()
                    }
                }
            )
        }
        .alert("Remove Member?", isPresented: $isRemoveDialogOpen) {
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task {
                        // TODO: Implement remove member API call
                        // For now, just refresh
                        await refreshData()
                        memberToRemove = nil
                    }
                }
            }
        } message: {
            if let member = memberToRemove {
                let name = member.user?.firstName ?? member.displayName
                Text("Are you sure you want to remove \(name) from \(group.name)? This action cannot be undone.")
            }
        }
    }

    private func refreshData() async {
        async let membersTask = try? appState.loadMembers(groupId: group.id)
        async let sessionsTask = try? appState.loadShoppingSessions(groupId: group.id)
        async let balancesTask = try? appState.loadBalances(groupId: group.id)
        _ = await (membersTask, sessionsTask, balancesTask)
    }
    
    // MARK: - Subviews
    
    private struct TotalSpentCard: View {
        let amountCents: Int
        let currency: String
        let subtitle: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Spent")
                    .font(ClearSplitTheme.Typography.overline)
                    .textCase(.uppercase)
                    .tracking(ClearSplitTheme.Tracking.extraWide)
                    .foregroundColor(Color.white.opacity(0.9))
                
                AnimatingCurrencyText(
                    value: amountCents,
                    currency: currency,
                    font: ClearSplitTheme.Typography.currencyHero,
                    tracking: ClearSplitTheme.Tracking.tight,
                    color: .white
                )
                
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Color.blue600)
            .cornerRadius(20)
            .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
        }
    }
    
    private struct MembersCard: View {
        let title: String
        let members: [Membership]
        let currentUserId: UUID?
        let groupName: String
        let onAddMember: () -> Void
        let onRemoveMember: (Membership) -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Header with Add button
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Color.textSecondary)
                        Text("\(title) (\(members.count))")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                            .tracking(-0.3)
                    }
                    
                    Spacer()
                    
                    Button(action: onAddMember) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 16, weight: .medium))
                            Text("Add")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandPrimary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.bottom, 16)
                
                // Member list
                if members.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No members yet")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.textSecondary)
                        Text("Invite your roommates to start splitting expenses.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                } else {
                    VStack(spacing: 12) {
                        ForEach(members) { member in
                            MemberRow(
                                member: member,
                                isCurrentUser: member.userId == currentUserId,
                                onRemove: { onRemoveMember(member) }
                            )
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionStyle()
        }
    }
    
    private struct MemberRow: View {
        let member: Membership
        let isCurrentUser: Bool
        let onRemove: () -> Void
        @State private var isHovered = false
        
        private var displayName: String {
            if let user = member.user {
                let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty {
                    return fullName
                }
                return user.email
            }
            return member.displayName
        }
        
        private var email: String? {
            member.user?.email
        }
        
        private var initials: String {
            if let user = member.user {
                let firstInitial = user.firstName.first.map(String.init) ?? ""
                let lastInitial = user.lastName.first.map(String.init) ?? ""
                let combined = (firstInitial + lastInitial)
                if !combined.isEmpty {
                    return combined.uppercased()
                }
            }
            return String(displayName.prefix(1)).uppercased()
        }
        
        private var avatarColor: (start: Color, end: Color) {
            let colors: [(Color, Color)] = [
                (Color(hex: "60A5FA"), Color.brandPrimary),
                (Color(hex: "38BDF8"), Color(hex: "0284C7")),
                (Color(hex: "4ADE80"), Color.success),
                (Color(hex: "14B8A6"), Color(hex: "0F766E")),
                (Color(hex: "818CF8"), Color(hex: "4F46E5")),
                (Color(hex: "64748B"), Color(hex: "334155"))
            ]
            // Use member ID to consistently assign colors
            let index = abs(member.id.hashValue) % colors.count
            return colors[index]
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [avatarColor.start, avatarColor.end],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text(initials)
                        .font(.system(size: initials.count > 1 ? 14 : 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // Content area
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isCurrentUser ? "You" : displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                        
                        if isCurrentUser {
                            Text("You")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.brandPrimaryPressed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.brandSurface)
                                .cornerRadius(8)
                        }
                    }
                    
                    if let email = email {
                        Text(email)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Remove button (only for non-current users)
                if !isCurrentUser {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isHovered ? Color.danger : Color.textMuted)
                            .frame(width: 28, height: 28)
                            .background(isHovered ? Color.dangerSurface : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(isHovered ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                }
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
    
    private struct AddMemberDialog: View {
        let groupName: String
        let groupId: UUID
        let members: [Membership]
        @ObservedObject var appState: AppState
        let onDismiss: () -> Void
        
        @State private var searchUserId = ""
        @State private var searchState: SearchState = .idle
        @State private var foundUser: User?
        @State private var errorMessage: String?
        
        @FocusState private var isInputFocused: Bool
        
        enum SearchState {
            case idle
            case searching
            case notFound
            case alreadyMember
            case found
        }
        
        private var canSearch: Bool {
            !searchUserId.trimmingCharacters(in: .whitespaces).isEmpty && searchState != .searching
        }
        
        private var canAdd: Bool {
            searchState == .found && foundUser != nil
        }
        
        var body: some View {
            ZStack {
                // Backdrop
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }
                
                // Dialog
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Section 1: Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add Member")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)
                                    .tracking(-0.4)
                                
                                Text("Search for a user by username to add them to \(groupName).")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.textSecondary)
                                    .lineSpacing(4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 16)
                            
                            // Section 2: Search Input Area
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Username")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.textPrimary)
                                
                                HStack(spacing: 8) {
                                    TextField("", text: $searchUserId)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(isInputFocused ? Color.cardBackground : Color.cardInset)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isInputFocused ? Color.brandPrimary : Color.borderLight, lineWidth: isInputFocused ? 2 : 1)
                                        )
                                        .disabled(searchState == .searching)
                                        .focused($isInputFocused)
                                        .onChange(of: searchUserId) { _ in
                                            if searchState != .idle {
                                                searchState = .idle
                                                foundUser = nil
                                            }
                                        }
                                        .onSubmit {
                                            if canSearch {
                                                handleSearchUser()
                                            }
                                        }
                                    
                                    Button(action: handleSearchUser) {
                                        HStack(spacing: 8) {
                                            if searchState == .searching {
                                                ProgressView()
                                                    .tint(.white)
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.system(size: 16, weight: .medium))
                                            }
                                            Text(searchState == .searching ? "Searching" : "Search")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .frame(height: 40)
                                        .background(canSearch ? Color.brandPrimary : Color.interactiveDisabled)
                                        .cornerRadius(8)
                                    }
                                    .disabled(!canSearch)
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                            .padding(.vertical, 16)
                            
                            // Section 3: Search Results Area
                            if searchState != .idle {
                                VStack(spacing: 0) {
                                    switch searchState {
                                    case .notFound:
                                        NotFoundResultCard(searchUserId: searchUserId)
                                    case .alreadyMember:
                                        if let user = foundUser {
                                            AlreadyMemberResultCard(user: user)
                                        }
                                    case .found:
                                        if let user = foundUser {
                                            FoundResultCard(user: user)
                                        }
                                    case .searching, .idle:
                                        EmptyView()
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(24)
                    }
                    
                    // Section 4: Dialog Footer
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.top, 16)
                        
                        HStack(spacing: 8) {
                            Button(action: onDismiss) {
                                Text("Cancel")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.textSecondary)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.interactiveDisabled, lineWidth: 1)
                                    )
                                    .cornerRadius(8)
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            Button(action: handleAddFoundUser) {
                                Text("Add Member")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .background(canAdd ? Color.brandPrimary : Color.interactiveDisabled)
                                    .cornerRadius(8)
                            }
                            .disabled(!canAdd)
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: 500)
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 16)
            }
            .onAppear {
                isInputFocused = true
            }
        }
        
        private func handleSearchUser() {
            let trimmedId = searchUserId.trimmingCharacters(in: .whitespaces)
            guard !trimmedId.isEmpty else { return }
            
            searchState = .searching
            foundUser = nil
            errorMessage = nil
            
            Task {
                do {
                    let preview = try await appState.previewMemberInvite(groupId: groupId, username: trimmedId)
                    
                    await MainActor.run {
                        if !preview.found {
                            searchState = .notFound
                            foundUser = nil
                        } else if preview.alreadyMember == true {
                            searchState = .alreadyMember
                            foundUser = preview.user
                        } else if let user = preview.user {
                            searchState = .found
                            foundUser = user
                        } else {
                            searchState = .notFound
                            foundUser = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        searchState = .notFound
                        foundUser = nil
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .server(_, let message):
                                errorMessage = message ?? "Failed to search for user"
                            default:
                                errorMessage = "Failed to search for user"
                            }
                        } else {
                            errorMessage = "Failed to search for user"
                        }
                    }
                }
            }
        }
        
        private func handleAddFoundUser() {
            guard let user = foundUser else { return }
            
            Task {
                do {
                    _ = try await appState.addMemberToGroup(groupId: groupId, username: user.username)
                    await MainActor.run {
                        resetDialog()
                        onDismiss()
                    }
                } catch {
                    await MainActor.run {
                        if let apiError = error as? APIError {
                            switch apiError {
                            case .server(_, let message):
                                errorMessage = message ?? "Failed to add member"
                            default:
                                errorMessage = "Failed to add member"
                            }
                        } else {
                            errorMessage = "Failed to add member"
                        }
                    }
                }
            }
        }
        
        private func resetDialog() {
            searchUserId = ""
            searchState = .idle
            foundUser = nil
            errorMessage = nil
        }
    }
    
    // MARK: - Result Cards
    
    private struct NotFoundResultCard: View {
        let searchUserId: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.danger)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("User Not Found")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.dangerHeading)
                    
                    Text("No user exists with username \"\(searchUserId)\". Please check and try again.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.dangerSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red300, lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
    
    private struct AlreadyMemberResultCard: View {
        let user: User
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.warning)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Already a Member")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.warningHeading)
                    
                    Text("\(user.displayName) (\(user.email)) is already a member of this group.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.warningText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.warningSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.warningBorder, lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
    
    private struct FoundResultCard: View {
        let user: User
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.success)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User Found")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.settledHeading)
                        
                        Text("Ready to add this user to your group.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.settledText)
                    }
                }
                
                // User Preview Card
                HStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(avatarGradient(for: user.id.uuidString))
                            .frame(width: 48, height: 48)
                        
                        Text(user.initials)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)
                        
                        Text(user.email)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.textTertiary)
                            .lineLimit(1)
                        
                        Text("ID: \(user.username)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.textMuted)
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.borderMedium, lineWidth: 1)
                )
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.settledSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.settledBorder, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        
        private func avatarGradient(for userId: String) -> LinearGradient {
            let colors: [(Color, Color)] = [
                (Color(hex: "60A5FA"), Color.brandPrimary),
                (Color(hex: "38BDF8"), Color(hex: "0284C7")),
                (Color(hex: "4ADE80"), Color.success),
                (Color(hex: "14B8A6"), Color(hex: "0F766E")),
                (Color(hex: "818CF8"), Color(hex: "4F46E5")),
                (Color(hex: "64748B"), Color(hex: "334155"))
            ]
            
            let hash = abs(userId.hashValue)
            let index = hash % colors.count
            let (start, end) = colors[index]
            
            return LinearGradient(
                gradient: Gradient(colors: [start, end]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private struct NavigationCardContent: View {
        let iconName: String
        let iconBackground: Color
        let iconColor: Color
        let title: String
        let subtitle: String
        
        var body: some View {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconBackground)
                        .frame(width: 48, height: 48)
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                            VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.gray900)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.gray600)
                }
                
                            Spacer()
                
                            Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color.gray400)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .sectionStyle()
        }
    }
    
    private struct NavigationCard<Content: View>: View {
        let iconName: String
        let iconBackground: Color
        let iconColor: Color
        let title: String
        let subtitle: String
        var isEnabled: Bool = true
        let destination: () -> Content
        
        init(
            iconName: String,
            iconBackground: Color,
            iconColor: Color,
            title: String,
            subtitle: String,
            isEnabled: Bool = true,
            destination: @escaping () -> Content
        ) {
            self.iconName = iconName
            self.iconBackground = iconBackground
            self.iconColor = iconColor
            self.title = title
            self.subtitle = subtitle
            self.isEnabled = isEnabled
            self.destination = destination
        }
        
        var body: some View {
            SwiftUI.Group {
                if isEnabled {
                    NavigationLink {
                        destination()
                    } label: {
                        NavigationCardContent(
                            iconName: iconName,
                            iconBackground: iconBackground,
                            iconColor: iconColor,
                            title: title,
                            subtitle: subtitle
                        )
                    }
                } else {
                    NavigationCardContent(
                        iconName: iconName,
                        iconBackground: iconBackground,
                        iconColor: iconColor,
                        title: title,
                        subtitle: subtitle
                    )
                    .opacity(0.6)
                }
            }
        }
    }
    
    private struct GroupHelpSheet: View {
        var body: some View {
            NavigationStack {
                List {
                    Section("Group Overview") {
                        Text("This screen shows your group's total spending, members, and quick links to shopping sessions and balances.")
                    }
                    
                    Section("Shopping Sessions") {
                        Text("Shopping sessions are grocery trips where you add items, choose who shares them, and ClearSplit calculates fair splits automatically.")
                    }
                    
                    Section("Balances & Settlement") {
                        Text("Balances show who owes whom based on all expenses. Settlements let you mark payments as paid so everyone can stay in sync.")
                    }
                }
                .navigationTitle("Group Help")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
