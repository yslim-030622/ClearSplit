import SwiftUI

struct ShoppingSessionsListView: View {
    @StateObject private var viewModel: ShoppingSessionsViewModel
    @State private var showingCreateSession = false
    @State private var isShowingHelp = false
    @State private var sessionPendingDelete: ShoppingSession?

    @ObservedObject private var appState: AppState
    let groupId: UUID
    let paidByMembershipId: UUID

    init(appState: AppState, groupId: UUID, paidByMembershipId: UUID) {
        _appState = ObservedObject(wrappedValue: appState)
        self.groupId = groupId
        self.paidByMembershipId = paidByMembershipId
        _viewModel = StateObject(wrappedValue: ShoppingSessionsViewModel(appState: appState, groupId: groupId))
    }

    private var members: [Membership] {
        appState.membershipsByGroupId[groupId] ?? []
    }

    private var currentUserId: UUID? {
        appState.user?.id
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            if viewModel.isLoading && viewModel.sessions.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShoppingSessionCardSkeleton()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .refreshable {
                    await viewModel.load()
                }
            } else if viewModel.sessions.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        VStack {
                            Spacer(minLength: 0)

                            VStack(spacing: 16) {
                                Image(systemName: "cart.badge.plus")
                                    .font(.system(size: 64, weight: .light))
                                    .foregroundColor(Color.textMuted)

                                Text("No Shopping Sessions Yet")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color.textPrimary)

                                Text("Create your first shopping session to start tracking expenses with your group.")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color.textTertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)

                                Button(action: { showingCreateSession = true }) {
                                    Text("Create Session")
                                        .font(ClearSplitTheme.Typography.bodyStrong)
                                        .foregroundColor(.textOnBrand)
                                        .frame(maxWidth: 200)
                                        .padding(.vertical, 12)
                                        .background(Color.brandPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                                }
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: geometry.size.height)
                        .padding(.horizontal, 16)
                    }
                    .refreshable {
                        await viewModel.load()
                    }
                }
            } else {
                List {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink {
                            ShoppingSessionDetailView(
                                appState: appState,
                                sessionId: session.id
                            )
                        } label: {
                            ShoppingSessionCard(
                                session: session,
                                members: members,
                                currentUserId: currentUserId
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                sessionPendingDelete = session
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
                    Color.clear.frame(height: 80)
                }
            }

            Button {
                isShowingHelp = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.textOnBrand)
                    .frame(width: 48, height: 48)
                    .background(Color.textPrimary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 54)
        }
        .navigationTitle("Shopping Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSession = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(Color.brandPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create Session")
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateShoppingSessionView(
                appState: appState,
                groupId: groupId,
                paidByMembershipId: paidByMembershipId,
                onCreated: {
                    showingCreateSession = false
                    Task { await viewModel.load() }
                }
            )
        }
        .sheet(isPresented: $isShowingHelp) {
            ShoppingSessionsHelpSheet()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Retry") { Task { await viewModel.load() } }
            Button("Cancel", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "Delete Session",
            isPresented: Binding(
                get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                sessionPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                let target = sessionPendingDelete
                sessionPendingDelete = nil
                if let target {
                    Task { await viewModel.delete(session: target) }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(sessionPendingDelete?.title ?? "")\"?")
        }
    }
}

struct ShoppingSessionCard: View {
    let session: ShoppingSession
    let members: [Membership]
    let currentUserId: UUID?

    private func formatDateString(_ dateString: String?) -> String {
        guard let dateString else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: date)
        }
        return dateString
    }

    private func getPaidByName() -> String {
        if let membership = members.first(where: { $0.id == session.paidByMembershipId }) {
            if let user = membership.user, user.id == currentUserId {
                return "You"
            }
            if let user = membership.user {
                return user.firstName.isEmpty ? user.displayName : user.firstName
            }
            return membership.displayName
        }
        return "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(session.title)
                    .font(ClearSplitTheme.Typography.sectionTitle)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)

                Spacer()

                Text(session.formattedTotal)
                    .font(ClearSplitTheme.Typography.currencyMedium)
                    .tracking(ClearSplitTheme.Tracking.wide)
                    .foregroundColor(Color.textPrimary)
            }
            .padding(20)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.textTertiary)

                Text(formatDateString(session.shoppingDate))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Spacer()
                .frame(height: 12)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cart")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.textTertiary)

                    Text("\(session.items.count) items")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.textTertiary)
                }

                Spacer()

                Text("Paid by \(getPaidByName())")
                    .font(ClearSplitTheme.Typography.subheadline)
                    .foregroundColor(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .cornerRadius(16)
        .applyElevation(.low)
    }
}

struct ShoppingSessionCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.borderMedium)
                    .frame(width: 150, height: 20)

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.borderMedium)
                    .frame(width: 80, height: 24)
            }
            .padding(20)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.borderMedium)
                .frame(width: 100, height: 14)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Spacer()
                .frame(height: 12)

            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.borderMedium)
                    .frame(width: 80, height: 14)

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.borderMedium)
                    .frame(width: 100, height: 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 112)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderMedium, lineWidth: 1)
        )
        .shimmer()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let shimmerColor = Color.white.opacity(colorScheme == .dark ? 0.08 : 0.6)
        
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            shimmerColor.opacity(0.3),
                            shimmerColor,
                            shimmerColor.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2.5)
                    .offset(x: -geometry.size.width * 1.5 + phase * geometry.size.width * 3)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

struct ShoppingSessionsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Shopping Sessions Help")
                        .font(.system(size: 24, weight: .bold))
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 16) {
                        HelpSection(
                            title: "What are Shopping Sessions?",
                            content: "Shopping sessions track group expenses from grocery trips and shopping. Each session contains items that can be split among group members."
                        )

                        HelpSection(
                            title: "Creating a Session",
                            content: "Tap the + button to create a new shopping session. You'll need to provide a name, date, and who paid for the trip."
                        )

                        HelpSection(
                            title: "Adding Items",
                            content: "Once a session is created, you can add items with prices. Items can be split among multiple members."
                        )

                        HelpSection(
                            title: "Viewing Details",
                            content: "Tap any session card to view its items, participants, and splitting details."
                        )
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private struct HelpSection: View {
        let title: String
        let content: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.textPrimary)

                Text(content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.textTertiary)
            }
        }
    }
}

extension ShoppingSession {
    var formattedTotal: String {
        let dollars = Double(totalCents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}
