import SwiftUI

struct GroupsListView: View {
    @StateObject private var viewModel: GroupsViewModel
    @ObservedObject private var appState: AppState
    @State private var showCreateGroup = false
    @State private var groupPendingDelete: Group?

    init(appState: AppState) {
        _appState = ObservedObject(wrappedValue: appState)
        _viewModel = StateObject(wrappedValue: GroupsViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.pageBackground
                    .ignoresSafeArea()

                content

                createGroupButton
            }
            .navigationTitle("My Groups")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateGroup, onDismiss: {
                Task { await viewModel.load() }
            }) {
                CreateGroupView()
                    .environmentObject(appState)
            }
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

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.groups.isEmpty {
            loadingView
        } else if viewModel.groups.isEmpty {
            emptyView
        } else {
            groupsList
        }
    }

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    GroupCardSkeleton()
                }
            }
            .padding(.horizontal, TabLayoutMetrics.horizontalPadding)
            .padding(.top, TabLayoutMetrics.topPadding)
            .padding(.bottom, TabLayoutMetrics.bottomPaddingForTabBar)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var emptyView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.3")
                    .font(.system(size: 64))
                    .foregroundColor(.textMuted)

                Text("No groups yet")
                    .font(ClearSplitTheme.Typography.title)
                    .foregroundColor(.textSecondary)

                Text("Create a group to start splitting expenses")
                    .font(ClearSplitTheme.Typography.body)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TabLayoutMetrics.horizontalPadding)
            .padding(.top, 88)
            .padding(.bottom, TabLayoutMetrics.bottomPaddingForTabBar)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var groupsList: some View {
        List {
            ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { index, group in
                GroupCard(group: group, appState: appState)
                    .staggeredAppearance(index: index)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(
                            top: index == 0 ? TabLayoutMetrics.topPadding : 6,
                            leading: TabLayoutMetrics.horizontalPadding,
                            bottom: 6,
                            trailing: TabLayoutMetrics.horizontalPadding
                        )
                    )
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
            Color.clear.frame(height: 88)
        }
    }

    private var createGroupButton: some View {
        Button(action: { showCreateGroup = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.body.weight(.semibold))

                Text("Create New Group")
                    .font(ClearSplitTheme.Typography.bodyStrong)
            }
            .foregroundColor(.textOnBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.brandPrimaryPressed],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .applyElevation(.medium)
        }
        .padding(.horizontal, TabLayoutMetrics.horizontalPadding)
        .padding(.bottom, 16)
        .accessibilityLabel("Create new group")
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
                        .font(ClearSplitTheme.Typography.sectionTitle)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .renderingMode(.template)
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                        
                        Text(memberLabel)
                            .font(ClearSplitTheme.Typography.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
                
                // Right: Balance
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if !isSettled {
                            Text("Your balance")
                                .font(ClearSplitTheme.Typography.caption)
                                .foregroundColor(.textTertiary)
                        }
                        
                        if isSettled {
                            Text("All settled up")
                                .font(ClearSplitTheme.Typography.subheadline)
                                .foregroundColor(.textTertiary)
                        } else {
                            Text(balanceText)
                                .font(ClearSplitTheme.Typography.currencyBody)
                                .tracking(ClearSplitTheme.Tracking.wide)
                                .foregroundColor(balanceColor)
                        }
                    }
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textMuted)
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
        userBalance > 0 ? .success : .danger
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
                    .fill(Color.gray200)
                    .frame(width: 120, height: 17)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray100)
                    .frame(width: 80, height: 14)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray100)
                    .frame(width: 70, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray200)
                    .frame(width: 60, height: 17)
            }
        }
        .padding(16)
        .frame(height: 72)
        .itemCardStyle()
    }
}
