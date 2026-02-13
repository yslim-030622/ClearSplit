import SwiftUI

@MainActor
struct BalancesSettlementView: View {
    @ObservedObject private var appState: AppState
    let group: Group

    @State private var individualBalances: [IndividualBalance] = []
    @State private var settlements: [SettlementPlan] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var pendingSettlementIds: Set<String> = []
    @State private var showError = false
    @State private var showSuccessToast = false
    @State private var errorMessage = ""

    init(appState: AppState, group: Group) {
        _appState = ObservedObject(wrappedValue: appState)
        self.group = group
    }

    private var currentMembership: Membership? {
        appState.getUserMembership(in: group.id)
    }

    private var activeSettlements: [SettlementPlan] {
        settlements.filter { !$0.isSettled }
    }

    private var showAllSettledState: Bool {
        !individualBalances.isEmpty &&
        activeSettlements.isEmpty &&
        individualBalances.allSatisfy { abs($0.balanceCents) <= 1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                individualBalancesSection

                if !settlements.isEmpty {
                    suggestedPaymentsSection
                }

                if showAllSettledState {
                    AllSettledCard()
                }

                InfoCard()
            }
            .padding(16)
        }
        .background(Color.pageBackground.ignoresSafeArea())
        .navigationTitle("Balances & Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshBalances()
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .scaleEffect(1.35)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.22))
            }
        }
        .overlay(alignment: .top) {
            if showSuccessToast {
                SuccessToast(message: "Settlement updated")
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await loadBalances()
        }
    }

    // MARK: - Sections

    private var individualBalancesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Individual Balances")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "111827"))

            if individualBalances.isEmpty {
                Text("No balances yet.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "6B7280"))
            } else {
                VStack(spacing: 12) {
                    ForEach(individualBalances) { balance in
                        IndividualBalanceRow(balance: balance)
                    }
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var suggestedPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Suggested Payments")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "111827"))

            VStack(spacing: 12) {
                ForEach(settlements) { settlement in
                    SettlementCard(
                        settlement: settlement,
                        canMarkAsPaid: canMarkSettlementAsPaid(settlement) && !isRefreshing,
                        isActionLoading: pendingSettlementIds.contains(settlement.id),
                        onMarkAsPaid: {
                            markSettlementAsPaid(settlement: settlement)
                        }
                    )
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Loading

    private func loadBalances() async {
        isLoading = true
        await reloadData()
        isLoading = false
    }

    private func refreshBalances() async {
        isRefreshing = true
        await reloadData()
        isRefreshing = false
    }

    private func reloadData() async {
        do {
            async let membersTask: Void = appState.loadMembers(groupId: group.id)
            async let sessionsTask: Void = appState.loadShoppingSessions(groupId: group.id)
            async let paymentsTask: Void = appState.loadSettlementPayments(groupId: group.id)
            async let balancesTask: Void = appState.loadBalances(groupId: group.id)
            _ = try await (membersTask, sessionsTask, paymentsTask, balancesTask)

            rebuildViewModels()
        } catch {
            errorMessage = "Failed to refresh balances."
            showError = true
        }
    }

    private func rebuildViewModels() {
        let memberships = appState.membershipsByGroupId[group.id] ?? []
        let membershipsById = Dictionary(uniqueKeysWithValues: memberships.map { ($0.id, $0) })
        let sessions = appState.shoppingSessionsByGroupId[group.id] ?? []
        let payments = appState.settlementPayments(for: group.id)

        var userNames: [UUID: String] = [:]
        for membership in memberships {
            userNames[membership.id] = membershipDisplayName(membership)
        }

        var balancesByMembership = BalanceCalculator.calculateIndividualBalances(
            from: sessions,
            confirmedPayments: payments
        )

        for membership in memberships where balancesByMembership[membership.id] == nil {
            balancesByMembership[membership.id] = 0
        }

        var balanceRows = balancesByMembership.map { membershipId, balanceCents in
            IndividualBalance(
                userId: membershipId,
                name: userNames[membershipId] ?? "Unknown",
                balanceCents: balanceCents,
                isSettled: abs(balanceCents) <= 1
            )
        }
        balanceRows.sort {
            if $0.name == "You" { return true }
            if $1.name == "You" { return false }
            if $0.balanceCents == $1.balanceCents {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.balanceCents > $1.balanceCents
        }

        let optimized = SettlementOptimizer.optimizeSettlements(
            balances: balancesByMembership,
            userNames: userNames
        )

        let settledHistory = payments
            .filter { $0.status.lowercased() == "confirmed" }
            .map { payment in
                SettlementPlan(
                    id: "payment-\(payment.id.uuidString)",
                    fromUserId: payment.fromMembership,
                    fromUserName: userNames[payment.fromMembership] ?? memberFallbackName(id: payment.fromMembership, map: membershipsById),
                    toUserId: payment.toMembership,
                    toUserName: userNames[payment.toMembership] ?? memberFallbackName(id: payment.toMembership, map: membershipsById),
                    amountCents: payment.amountCents,
                    isSettled: true,
                    settledAt: payment.confirmedAt ?? payment.sentAt ?? payment.createdAt
                )
            }

        var allSettlements = optimized + settledHistory
        allSettlements.sort {
            if $0.isSettled != $1.isSettled {
                return !$0.isSettled && $1.isSettled
            }
            if $0.amountCents == $1.amountCents {
                return $0.fromUserName.localizedCaseInsensitiveCompare($1.fromUserName) == .orderedAscending
            }
            return $0.amountCents > $1.amountCents
        }

        individualBalances = balanceRows
        settlements = allSettlements
    }

    // MARK: - Interactions

    private func canMarkSettlementAsPaid(_ settlement: SettlementPlan) -> Bool {
        guard let membership = currentMembership else { return false }
        if membership.role.lowercased() == "owner" {
            return true
        }
        return membership.id == settlement.fromUserId || membership.id == settlement.toUserId
    }

    private func markSettlementAsPaid(settlement: SettlementPlan) {
        guard !settlement.isSettled else { return }
        guard !isRefreshing else { return }
        guard !pendingSettlementIds.contains(settlement.id) else { return }
        guard canMarkSettlementAsPaid(settlement) else { return }

        pendingSettlementIds.insert(settlement.id)

        if let index = settlements.firstIndex(where: { $0.id == settlement.id }) {
            settlements[index].isSettled = true
            settlements[index].settledAt = Date()
        }

        Task {
            do {
                let request = SettlementPaymentCreateRequest(
                    fromMembership: settlement.fromUserId,
                    toMembership: settlement.toUserId,
                    amountCents: settlement.amountCents,
                    autoConfirm: true
                )
                _ = try await appState.createSettlementPayment(groupId: group.id, request: request)
                rebuildViewModels()
                await showSuccess()
            } catch {
                if let index = settlements.firstIndex(where: { $0.id == settlement.id }) {
                    settlements[index].isSettled = false
                    settlements[index].settledAt = nil
                }
                errorMessage = "Failed to mark as settled. Please try again."
                showError = true
            }

            pendingSettlementIds.remove(settlement.id)
        }
    }

    private func showSuccess() async {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showSuccessToast = true
        }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showSuccessToast = false
        }
    }

    // MARK: - Name Helpers

    private func membershipDisplayName(_ membership: Membership) -> String {
        if membership.id == currentMembership?.id {
            return "You"
        }

        guard let user = membership.user else {
            return membership.displayName
        }

        let fullName = "\(user.firstName) \(user.lastName)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        return user.email
    }

    private func memberFallbackName(id: UUID, map: [UUID: Membership]) -> String {
        if let membership = map[id] {
            return membershipDisplayName(membership)
        }
        return "Member \(id.uuidString.prefix(4).uppercased())"
    }
}

private struct IndividualBalanceRow: View {
    let balance: IndividualBalance

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Text(balance.name.prefix(1).uppercased())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                )

            Text(balance.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "111827"))

            Spacer()

            balanceDisplay
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var balanceDisplay: some View {
        switch balance.balanceStatus {
        case .settled:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "059669"))
                Text("Settled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "059669"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "D1FAE5"))
            .cornerRadius(8)

        case .owed:
            VStack(alignment: .trailing, spacing: 2) {
                Text("gets back")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "6B7280"))
                Text("+$\(balance.balance, specifier: "%.2f")")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "10B981"))
            }

        case .owes:
            VStack(alignment: .trailing, spacing: 2) {
                Text("owes")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "6B7280"))
                Text("$\(abs(balance.balance), specifier: "%.2f")")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "EF4444"))
            }

        case .even:
            Text("Even")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "6B7280"))
        }
    }
}

private struct SettlementCard: View {
    let settlement: SettlementPlan
    let canMarkAsPaid: Bool
    let isActionLoading: Bool
    let onMarkAsPaid: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    avatarView(for: settlement.fromUserName, color: "3B82F6")
                    Text(settlement.fromUserName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "111827"))
                }

                Spacer()

                Image(systemName: settlement.isSettled ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.system(size: 18))
                    .foregroundColor(settlement.isSettled ? Color(hex: "10B981") : Color(hex: "9CA3AF"))

                Spacer()

                HStack(spacing: 8) {
                    Text(settlement.toUserName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "111827"))
                    avatarView(for: settlement.toUserName, color: "A855F7")
                }
            }

            Divider()
                .background(Color(hex: "E5E7EB"))

            HStack {
                Text("$\(settlement.amount, specifier: "%.2f")")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "111827"))

                Spacer()

                if settlement.isSettled {
                    settledBadge
                } else {
                    markAsPaidButton
                }
            }
        }
        .padding(16)
        .background(settlement.isSettled ? Color(hex: "F0FDF4") : Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    settlement.isSettled ? Color(hex: "86EFAC") : Color.borderMedium,
                    lineWidth: 1.5
                )
        )
        .cornerRadius(12)
    }

    private func avatarView(for name: String, color: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: color).opacity(0.8), Color(hex: color)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 32, height: 32)
            .overlay(
                Text(name.prefix(1).uppercased())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            )
    }

    private var settledBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
            Text("Settled")
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(Color(hex: "059669"))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: "D1FAE5"))
        .cornerRadius(8)
    }

    private var markAsPaidButton: some View {
        Button(action: onMarkAsPaid) {
            HStack(spacing: 6) {
                if isActionLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text("Mark as Paid")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(hex: "2563EB"))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!canMarkAsPaid || isActionLoading)
        .opacity(canMarkAsPaid ? 1 : 0.45)
    }
}

private struct AllSettledCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color(hex: "D1FAE5"))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "10B981"))
                )

            Text("All Settled Up!")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "111827"))

            Text("Everyone in this group is even")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "6B7280"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            LinearGradient(
                colors: [Color(hex: "F0FDF4"), Color(hex: "D1FAE5")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "86EFAC"), lineWidth: 2)
        )
        .cornerRadius(16)
    }
}

private struct InfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How settlements work")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "1E3A8A"))

            VStack(alignment: .leading, spacing: 4) {
                InfoRow(text: "Balances are calculated from all shopping sessions")
                InfoRow(text: "Each person pays their share of items they selected")
                InfoRow(text: "Mark payments as settled when complete")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "DBEAFE"))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "BFDBFE"), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

private struct InfoRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1E40AF"))
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1E40AF"))
        }
    }
}

private struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "059669"))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "064E3B"))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "D1FAE5"))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "86EFAC"), lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
