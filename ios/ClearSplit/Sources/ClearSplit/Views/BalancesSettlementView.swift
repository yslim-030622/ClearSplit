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

    private var settledSettlements: [SettlementPlan] {
        settlements.filter { $0.isSettled }
    }

    private var visibleSuggestedSettlements: [SettlementPlan] {
        guard let membership = currentMembership else { return [] }
        return activeSettlements.filter { $0.fromUserId == membership.id }
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

                if !visibleSuggestedSettlements.isEmpty {
                    suggestedPaymentsSection
                }

                if !settledSettlements.isEmpty {
                    paymentHistorySection
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
                .foregroundColor(Color.textPrimary)

            if individualBalances.isEmpty {
                Text("No balances yet.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.textTertiary)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(individualBalances.enumerated()), id: \.element.id) { index, balance in
                        IndividualBalanceRow(balance: balance)
                            .staggeredAppearance(index: index)
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
                .foregroundColor(Color.textPrimary)

            VStack(spacing: 12) {
                ForEach(visibleSuggestedSettlements) { settlement in
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

    private var paymentHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Payment History")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.textPrimary)

            VStack(spacing: 12) {
                ForEach(settledSettlements) { settlement in
                    SettlementCard(
                        settlement: settlement,
                        canMarkAsPaid: false,
                        isActionLoading: false,
                        onMarkAsPaid: {}
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
            try await appState.loadBalances(groupId: group.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Failed to refresh balances."
            showError = true
            return
        }

        do {
            try await appState.loadMembers(groupId: group.id)
        } catch is CancellationError {
            return
        } catch {
            print("⚠️ BalancesSettlementView: members refresh failed: \(error)")
        }

        do {
            try await appState.loadSettlementPayments(groupId: group.id)
        } catch is CancellationError {
            return
        } catch {
            print("⚠️ BalancesSettlementView: settlement payments refresh failed: \(error)")
        }

        rebuildViewModels()
    }

    private func rebuildViewModels() {
        let memberships = appState.membershipsByGroupId[group.id] ?? []
        let membershipsById = Dictionary(uniqueKeysWithValues: memberships.map { ($0.id, $0) })
        let groupBalances = appState.balances(for: group.id)
        let payments = appState.settlementPayments(for: group.id)

        var userNames: [UUID: String] = [:]
        for membership in memberships {
            userNames[membership.id] = membershipDisplayName(membership)
        }

        var balancesByMembership: [UUID: Int] = [:]
        for balance in groupBalances?.balances ?? [] {
            balancesByMembership[balance.membershipId] = balance.netCents
        }

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
        balanceRows = sortBalanceRows(balanceRows)

        let suggestedPayments = (groupBalances?.suggestions ?? [])
            .map { suggestion in
                SettlementPlan(
                    id: suggestion.id,
                    fromUserId: suggestion.fromMembership,
                    fromUserName: userNames[suggestion.fromMembership] ?? memberFallbackName(id: suggestion.fromMembership, map: membershipsById),
                    toUserId: suggestion.toMembership,
                    toUserName: userNames[suggestion.toMembership] ?? memberFallbackName(id: suggestion.toMembership, map: membershipsById),
                    amountCents: suggestion.amountCents,
                    isSettled: false,
                    settledAt: nil
                )
            }
            .sorted {
                if $0.amountCents == $1.amountCents {
                    return $0.fromUserName.localizedCaseInsensitiveCompare($1.fromUserName) == .orderedAscending
                }
                return $0.amountCents > $1.amountCents
            }

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
            .sorted {
                let lhsDate = $0.settledAt ?? .distantPast
                let rhsDate = $1.settledAt ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.amountCents > $1.amountCents
                }
                return lhsDate > rhsDate
            }

        individualBalances = balanceRows
        settlements = suggestedPayments + settledHistory
    }

    // MARK: - Interactions

    private func canMarkSettlementAsPaid(_ settlement: SettlementPlan) -> Bool {
        guard let membership = currentMembership else { return false }
        return membership.id == settlement.fromUserId
    }

    private func markSettlementAsPaid(settlement: SettlementPlan) {
        guard !settlement.isSettled else { return }
        guard !isRefreshing else { return }
        guard !pendingSettlementIds.contains(settlement.id) else { return }
        guard canMarkSettlementAsPaid(settlement) else { return }

        pendingSettlementIds.insert(settlement.id)
        let previousBalances = individualBalances
        let previousSettlements = settlements
        applyOptimisticSettlement(settlement)

        Task {
            do {
                let request = SettlementPaymentCreateRequest(
                    fromMembership: settlement.fromUserId,
                    toMembership: settlement.toUserId,
                    amountCents: settlement.amountCents,
                    autoConfirm: true
                )
                _ = try await appState.createSettlementPayment(groupId: group.id, request: request)
                await reloadData()
                await showSuccess()
            } catch {
                individualBalances = previousBalances
                settlements = previousSettlements
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

    private func applyOptimisticSettlement(_ settlement: SettlementPlan) {
        settlements.removeAll { $0.id == settlement.id }

        var balancesByMembership = Dictionary(
            uniqueKeysWithValues: individualBalances.map { ($0.userId, $0.balanceCents) }
        )
        balancesByMembership[settlement.fromUserId, default: 0] += settlement.amountCents
        balancesByMembership[settlement.toUserId, default: 0] -= settlement.amountCents

        let userNames = Dictionary(
            uniqueKeysWithValues: individualBalances.map { ($0.userId, $0.name) }
        )
        let rows = balancesByMembership.map { membershipId, balanceCents in
            IndividualBalance(
                userId: membershipId,
                name: userNames[membershipId] ?? "Unknown",
                balanceCents: balanceCents,
                isSettled: abs(balanceCents) <= 1
            )
        }
        individualBalances = sortBalanceRows(rows)
    }

    private func sortBalanceRows(_ rows: [IndividualBalance]) -> [IndividualBalance] {
        rows.sorted {
            if $0.name == "You" { return true }
            if $1.name == "You" { return false }
            if $0.balanceCents == $1.balanceCents {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.balanceCents > $1.balanceCents
        }
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
                .foregroundColor(Color.textPrimary)

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
                    .foregroundColor(Color.success)
                Text("Settled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.success)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.successSurface)
            .cornerRadius(8)

        case .owed:
            VStack(alignment: .trailing, spacing: 2) {
                Text("gets back")
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
                Text("+$\(balance.balance, specifier: "%.2f")")
                    .font(ClearSplitTheme.Typography.currencyBody)
                    .tracking(ClearSplitTheme.Tracking.wide)
                    .foregroundColor(Color.success)
            }

        case .owes:
            VStack(alignment: .trailing, spacing: 2) {
                Text("owes")
                    .font(.system(size: 13))
                    .foregroundColor(Color.textTertiary)
                Text("$\(abs(balance.balance), specifier: "%.2f")")
                    .font(ClearSplitTheme.Typography.currencyBody)
                    .tracking(ClearSplitTheme.Tracking.wide)
                    .foregroundColor(Color.danger)
            }

        case .even:
            Text("Even")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.textTertiary)
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
                        .foregroundColor(Color.textPrimary)
                }

                Spacer()

                Image(systemName: settlement.isSettled ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.system(size: 18))
                    .foregroundColor(settlement.isSettled ? Color.success : Color.textMuted)

                Spacer()

                HStack(spacing: 8) {
                    Text(settlement.toUserName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.textPrimary)
                    avatarView(for: settlement.toUserName, color: "A855F7")
                }
            }

            Divider()
                .background(Color.borderMedium)

            HStack {
                Text("$\(settlement.amount, specifier: "%.2f")")
                    .font(ClearSplitTheme.Typography.currencyLarge)
                    .tracking(ClearSplitTheme.Tracking.wide)
                    .foregroundColor(Color.textPrimary)

                Spacer()

                if settlement.isSettled {
                    settledBadge
                } else {
                    markAsPaidButton
                }
            }
        }
        .padding(16)
        .background(settlement.isSettled ? Color.settledSurface : Color.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    settlement.isSettled ? Color.settledBorder : Color.borderMedium,
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
        .foregroundColor(Color.success)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.successSurface)
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
            .background(Color.brandPrimary)
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
                .fill(Color.successSurface)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color.success)
                )

            Text("All Settled Up!")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.textPrimary)

            Text("Everyone in this group is even")
                .font(.system(size: 15))
                .foregroundColor(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color.white, Color.settledSurface, Color.successSurface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.8), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 150
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.settledBorder, lineWidth: 2)
        )
        .cornerRadius(16)
    }
}

private struct InfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How settlements work")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.infoText)

            VStack(alignment: .leading, spacing: 4) {
                InfoRow(text: "Balances are calculated from all shopping sessions")
                InfoRow(text: "Each person pays their share of items they selected")
                InfoRow(text: "Mark payments as settled when complete")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.infoSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.infoBorder, lineWidth: 1)
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
                .foregroundColor(Color.infoText)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Color.infoText)
        }
    }
}

private struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color.success)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.settledHeading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.successSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.settledBorder, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}
