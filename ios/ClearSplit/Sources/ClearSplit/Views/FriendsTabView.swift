import SwiftUI

#if os(iOS)
import UIKit
#endif

struct FriendsTabView: View {
    @StateObject private var viewModel: FriendsViewModel
    @State private var searchQuery = ""
    @State private var showAddFriend = false
    @State private var inputType: FriendInputType = .email
    @State private var newFriendInput = ""
    @State private var selectedFriend: Friend?

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: FriendsViewModel(appState: appState))
    }

    private var friendRequests: [FriendRequest] {
        viewModel.incomingRequests.map(FriendRequest.init(friendship:))
    }

    private var allFriends: [Friend] {
        viewModel.friends.map(Friend.init(friendship:))
    }

    private var filteredFriends: [Friend] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allFriends }

        return allFriends.filter { friend in
            friend.name.localizedCaseInsensitiveContains(trimmed) ||
                friend.handle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TabLayoutMetrics.sectionSpacing) {
                    searchField

                    if showAddFriend {
                        addFriendForm
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if viewModel.isLoading && allFriends.isEmpty && friendRequests.isEmpty {
                        loadingCard
                    } else {
                        if !friendRequests.isEmpty {
                            friendRequestsSection
                        }

                        if !viewModel.outgoingRequests.isEmpty {
                            outgoingRequestsSection
                        }

                        friendsListSection
                    }

                    infoBox
                }
                .padding(.horizontal, TabLayoutMetrics.horizontalPadding)
                .padding(.top, TabLayoutMetrics.topPadding)
                .padding(.bottom, TabLayoutMetrics.bottomPaddingForTabBar)
            }
            .refreshable {
                await viewModel.load()
            }
            .background(Color.pageBackground)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addFriendToolbarButton
                }
            }
        }
        .background(Color.pageBackground.ignoresSafeArea())
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

    private var addFriendToolbarButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showAddFriend.toggle()
                if !showAddFriend {
                    newFriendInput = ""
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: showAddFriend ? "xmark" : "person.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                Text(showAddFriend ? "Close" : "Add")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue600)
            .cornerRadius(10)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.gray400)

            TextField("Search friends...", text: $searchQuery)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(12)
        .background(Color.cardInset)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderLight, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var addFriendForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add New Friend")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)

            HStack(spacing: 8) {
                inputTypeButton(.email, title: "Email / Username")
                inputTypeButton(.id, title: "User ID")
            }
            .padding(4)
            .background(Color.cardInset)
            .cornerRadius(8)

            TextField(
                inputType == .email ? "Enter email or username" : "Enter user ID",
                text: $newFriendInput
            )
            .font(.system(size: 14))
            .padding(10)
            .background(Color.cardInset)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
            .cornerRadius(10)
            .textInputAutocapitalization(.never)
            .keyboardType(inputType == .email ? .emailAddress : .default)

            Text(
                inputType == .email
                    ? "Enter your friend's email address or username"
                    : "Enter your friend's user ID"
            )
            .font(.system(size: 12))
            .foregroundColor(.gray500)

            HStack(spacing: 8) {
                Button(action: sendFriendRequest) {
                    ZStack {
                        if viewModel.isSubmittingRequest {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Send Request")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        sanitizedNewFriendInput.isEmpty || viewModel.isSubmittingRequest
                            ? Color.gray300
                            : Color.blue600
                    )
                    .cornerRadius(8)
                }
                .disabled(sanitizedNewFriendInput.isEmpty || viewModel.isSubmittingRequest)

                Button(action: {
                    withAnimation(.spring()) {
                        showAddFriend = false
                        newFriendInput = ""
                    }
                }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray700)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.borderMedium, lineWidth: 1)
                        )
                        .cornerRadius(8)
                }
                .disabled(viewModel.isSubmittingRequest)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading friends...")
                .font(.system(size: 14))
                .foregroundColor(.gray600)
            Spacer()
        }
        .padding(20)
        .cardStyle()
    }

    private var friendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friend Requests")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)

            VStack(spacing: 12) {
                ForEach(friendRequests) { request in
                    FriendRequestRow(
                        request: request,
                        onAccept: { accept(request) },
                        onReject: { reject(request) }
                    )
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var outgoingRequestsSection: some View {
        let names = viewModel.outgoingRequests.map { $0.friend.displayName }.joined(separator: ", ")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue700)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pending requests: \(viewModel.outgoingRequests.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue800)
                Text(names)
                    .font(.system(size: 13))
                    .foregroundColor(.blue700)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.blue100)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Friends")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)

                Spacer()

                Text("\(filteredFriends.count) friends")
                    .font(.system(size: 14))
                    .foregroundColor(.gray500)
            }

            if filteredFriends.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 42))
                        .foregroundColor(.gray300)
                    Text("No friends found")
                        .font(.system(size: 15))
                        .foregroundColor(.gray500)
                    if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Try a different search")
                            .font(.system(size: 13))
                            .foregroundColor(.gray400)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredFriends) { friend in
                        Button(action: {
                            selectedFriend = friend
                            triggerImpactFeedback()
                        }) {
                            FriendRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .cardStyle()
        .sheet(item: $selectedFriend) { friend in
            FriendDetailSheet(friend: friend) { target in
                removeFriend(target)
            }
        }
    }

    private var infoBox: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 18))
                .foregroundColor(.blue800)

            Text("Add friends to easily create groups and split expenses together")
                .font(.system(size: 14))
                .foregroundColor(.blue800)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.blue100)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var sanitizedNewFriendInput: String {
        newFriendInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inputTypeButton(_ type: FriendInputType, title: String) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                inputType = type
                newFriendInput = ""
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(inputType == type ? .blue600 : .gray500)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(inputType == type ? Color.cardBackground : Color.clear)
                .cornerRadius(6)
                .shadow(color: inputType == type ? Color.black.opacity(0.05) : .clear, radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func sendFriendRequest() {
        guard !sanitizedNewFriendInput.isEmpty else { return }
        let requestInput = sanitizedNewFriendInput
        Task {
            let success = await viewModel.sendFriendRequest(input: requestInput, inputType: inputType)
            guard success else { return }
            await MainActor.run {
                withAnimation(.spring()) {
                    showAddFriend = false
                    newFriendInput = ""
                }
                triggerNotificationFeedback()
            }
        }
    }

    private func accept(_ request: FriendRequest) {
        Task {
            let success = await viewModel.acceptFriendRequest(friendshipID: request.id)
            if success {
                await MainActor.run {
                    triggerNotificationFeedback()
                }
            }
        }
    }

    private func reject(_ request: FriendRequest) {
        Task {
            _ = await viewModel.declineFriendRequest(friendshipID: request.id)
        }
    }

    private func removeFriend(_ friend: Friend) {
        Task {
            _ = await viewModel.removeFriend(friendshipID: friend.id)
        }
    }

    private func triggerImpactFeedback() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    private func triggerNotificationFeedback() {
#if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }
}

enum FriendInputType {
    case email
    case id
}

struct FriendDetailSheet: View {
    let friend: Friend
    let onRemove: (Friend) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray300)
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue500, .blue700],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(String(friend.name.prefix(1)))
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(.white)
                            )

                        Text(friend.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.gray900)

                        Text(friend.handle)
                            .font(.system(size: 14))
                            .foregroundColor(.gray500)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        detailInfoRow(
                            icon: "calendar",
                            title: "Friends Since",
                            value: friend.joinedDate ?? "Unknown"
                        )

                        detailInfoRow(
                            icon: "person.2",
                            title: "Groups in Common",
                            value: "\(friend.groupsInCommon ?? 0)"
                        )
                    }

                    VStack(spacing: 12) {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Close")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.gray700)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.borderMedium, lineWidth: 1)
                                )
                                .cornerRadius(12)
                        }

                        Button(action: {
                            onRemove(friend)
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.xmark")
                                    .font(.system(size: 14))
                                Text("Remove Friend")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(.red600)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red300, lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 20)
            }
        }
        .background(Color.cardBackground)
#if os(iOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
#endif
    }

    private func detailInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.gray500)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.cardInset)
        .cornerRadius(12)
    }
}

struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue500, .blue700],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(friend.name.prefix(1)))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                Text(friend.handle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray400)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct FriendRequestRow: View {
    let request: FriendRequest
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "8B5CF6"), Color(hex: "6366F1")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(request.name.prefix(1)))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                Text(request.handle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray500)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "059669"))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "D1FAE5"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red600)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "FEE2E2"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct Friend: Identifiable, Equatable {
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    let id: UUID
    let userId: UUID
    let username: String
    let name: String
    let handle: String
    let joinedDate: String?
    let groupsInCommon: Int?

    init(friendship: Friendship) {
        id = friendship.id
        userId = friendship.friend.id
        username = friendship.friend.username
        name = friendship.friend.displayName
        handle = friendship.friend.handle
        joinedDate = Self.monthYearFormatter.string(from: friendship.createdAt)
        groupsInCommon = nil
    }
}

struct FriendRequest: Identifiable {
    let id: UUID
    let userId: UUID
    let username: String
    let name: String
    let handle: String

    init(friendship: Friendship) {
        id = friendship.id
        userId = friendship.friend.id
        username = friendship.friend.username
        name = friendship.friend.displayName
        handle = friendship.friend.handle
    }
}
