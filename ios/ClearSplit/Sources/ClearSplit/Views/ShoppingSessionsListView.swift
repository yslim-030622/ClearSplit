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
            Color(hex: "F9FAFB")
                .ignoresSafeArea()

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
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(Color(hex: "9CA3AF"))

                        Text("No Shopping Sessions Yet")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(hex: "111827"))

                        Text("Create your first shopping session to start tracking expenses with your group.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color(hex: "6B7280"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button(action: { showingCreateSession = true }) {
                            Text("Create Session")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: 200)
                                .padding(.vertical, 12)
                                .background(Color(hex: "2563EB"))
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 100)
                }
                .refreshable {
                    await viewModel.load()
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
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(hex: "1F2937"))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.trailing, 20)
            .padding(.bottom, 54)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Shopping Sessions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateSession = true }) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "2563EB"))
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(hex: "2563EB").opacity(0.3), radius: 8, x: 0, y: 2)

                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "111827"))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)

                Spacer()

                Text(session.formattedTotal)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundColor(Color(hex: "111827"))
            }
            .padding(20)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))

                Text(formatDateString(session.shoppingDate))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Spacer()
                .frame(height: 12)

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cart")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))

                    Text("\(session.items.count) items")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(hex: "6B7280"))
                }

                Spacer()

                Text("Paid by \(getPaidByName())")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(hex: "4B5563"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}

struct ShoppingSessionCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 150, height: 20)

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 80, height: 24)
            }
            .padding(20)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "E5E7EB"))
                .frame(width: 100, height: 14)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            Spacer()
                .frame(height: 12)

            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 80, height: 14)

                Spacer()

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "E5E7EB"))
                    .frame(width: 100, height: 14)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 112)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
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

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear,
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
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
                    .foregroundColor(Color(hex: "111827"))

                Text(content)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "6B7280"))
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
