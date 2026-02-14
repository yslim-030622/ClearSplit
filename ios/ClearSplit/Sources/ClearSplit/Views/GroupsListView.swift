import SwiftUI

struct GroupsListView: View {
    @StateObject private var viewModel: GroupsViewModel
    @ObservedObject private var appState: AppState
    let onLogout: () -> Void
    @State private var showCreateGroup = false
    @State private var showLogoutAlert = false
    @State private var groupPendingDelete: Group?

    init(appState: AppState, onLogout: @escaping () -> Void) {
        _appState = ObservedObject(wrappedValue: appState)
        _viewModel = StateObject(wrappedValue: GroupsViewModel(appState: appState))
        self.onLogout = onLogout
    }

    private var headerRow: some View {
        HStack {
            Text("My Groups")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "111827"))
                .tracking(-0.5)

            Spacer()

            Button(action: { showLogoutAlert = true }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(hex: "2563EB"))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Log out")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                Color.pageBackground
                    .ignoresSafeArea()
                
                // Content
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            headerRow
                                .padding(.horizontal, 16)
                                .padding(.top, 47 + 8) // Safe area + spacing

                            VStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    GroupCardSkeleton()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                        }
                    }
                    .refreshable {
                        await viewModel.load()
                    }
                } else if viewModel.groups.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            headerRow
                                .padding(.horizontal, 16)
                                .padding(.top, 47 + 8) // Safe area + spacing

                            VStack(spacing: 16) {
                                Image(systemName: "person.3")
                                    .font(.system(size: 64))
                                    .foregroundColor(Color(hex: "D1D5DB"))

                                Text("No groups yet")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(hex: "4B5563"))

                                Text("Create a group to start splitting expenses")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(Color(hex: "6B7280"))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                            .padding(.bottom, 100)
                        }
                    }
                    .refreshable {
                        await viewModel.load()
                    }
                } else {
                    List {
                        headerRow
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 47 + 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)

                        ForEach(viewModel.groups) { group in
                            GroupCard(group: group, appState: appState)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        groupPendingDelete = group
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .refreshable {
                        await viewModel.load()
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 100)
                    }
                }
                
                // Bottom Button
                Button(action: { showCreateGroup = true }) {
                    Text("Create New Group")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(hex: "2563EB"))
                        .cornerRadius(12)
                        .shadow(color: Color(hex: "2563EB").opacity(0.2), radius: 8, y: 2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34 + 16) // Safe area + margin
                .accessibilityLabel("Create new group")
            }
            .sheet(isPresented: $showCreateGroup, onDismiss: {
                Task { await viewModel.load() }
            }) {
                CreateGroupView()
                    .environmentObject(appState)
            }
        }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                onLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert(
            "Delete Group",
            isPresented: Binding(
                get: { groupPendingDelete != nil },
                set: { if !$0 { groupPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                groupPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                let target = groupPendingDelete
                groupPendingDelete = nil
                if let target {
                    Task { await viewModel.delete(group: target) }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(groupPendingDelete?.name ?? "")\"?")
        }
        .task {
            await viewModel.load()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct GroupCard: View {
    let group: Group
    @ObservedObject var appState: AppState
    @State private var isHovered = false
    @State private var hasRequestedMembers = false

    private var memberCount: Int {
        if let loadedCount = appState.membershipsByGroupId[group.id]?.count {
            return loadedCount
        }
        return group.userMembershipId == nil ? 0 : 1
    }
    
    private var userBalance: Decimal {
        guard let myMembershipId = appState.getUserMembership(in: group.id)?.id else {
            return 0
        }
        let netCents = appState.netBalanceCents(groupId: group.id, membershipId: myMembershipId)
        return Decimal(netCents) / 100
    }
    
    private var isSettled: Bool {
        userBalance == 0
    }
    
    var body: some View {
        NavigationLink(destination: GroupDetailView(appState: appState, group: group)) {
            HStack(spacing: 0) {
                // Left: Group info
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "111827"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .renderingMode(.template)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                        
                        Text(memberLabel)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(hex: "4B5563"))
                    }
                }
                
                Spacer()
                
                // Right: Balance
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !isSettled {
                            Text("Your balance")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        }
                        
                        if isSettled {
                            Text("All settled up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color(hex: "6B7280"))
                        } else {
                            Text(balanceText)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(balanceColor)
                        }
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
            }
            .padding(16)
            .frame(height: 72)
            .itemCardStyle(isHovered: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            guard appState.membershipsByGroupId[group.id] == nil else { return }
            guard !hasRequestedMembers else { return }

            hasRequestedMembers = true
            Task {
                try? await appState.loadMembers(groupId: group.id)
            }
        }
    }
    
    private var balanceText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = group.currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        
        let amount = abs(userBalance)
        let formatted = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
        
        return userBalance > 0 ? "+\(formatted)" : formatted
    }
    
    private var balanceColor: Color {
        userBalance > 0 ? Color(hex: "16A34A") : Color(hex: "DC2626")
    }

    private var memberLabel: String {
        return "\(memberCount) \(memberCount == 1 ? "member" : "members")"
    }
}

struct GroupCardSkeleton: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 120, height: 17)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 80, height: 14)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 70, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 60, height: 17)
            }
        }
        .padding(16)
        .frame(height: 72)
        .itemCardStyle()
    }
}
