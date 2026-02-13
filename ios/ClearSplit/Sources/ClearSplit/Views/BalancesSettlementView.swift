import SwiftUI

@MainActor
struct BalancesSettlementView: View {
    @ObservedObject private var appState: AppState
    let group: Group

    @State private var errorMessage: String?
    @State private var inFlightActionIds: Set<String> = []

    init(appState: AppState, group: Group) {
        _appState = ObservedObject(wrappedValue: appState)
        self.group = group
    }

    private var currentMembership: Membership? {
        appState.getUserMembership(in: group.id)
    }

    private var balances: GroupBalances? {
        appState.balances(for: group.id)
    }

    private var suggestions: [SettlementSuggestion] {
        balances?.suggestions ?? []
    }

    private var currentNetCents: Int {
        guard let membershipId = currentMembership?.id else { return 0 }
        return appState.netBalanceCents(groupId: group.id, membershipId: membershipId)
    }

    private var directSuggestions: [SettlementSuggestion] {
        guard let membershipId = currentMembership?.id else { return [] }
        return suggestions.filter { suggestion in
            suggestion.fromMembership == membershipId || suggestion.toMembership == membershipId
        }
    }

    private var paymentHistory: [SettlementPayment] {
        appState.settlementPayments(for: group.id)
    }

    private var youOweCents: Int {
        max(-currentNetCents, 0)
    }

    private var youAreOwedCents: Int {
        max(currentNetCents, 0)
    }

    private var isSettled: Bool {
        currentNetCents == 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                directDebtsSection
                suggestionsSection
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color.gray50.ignoresSafeArea())
        .navigationTitle("Balances & Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Summary")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)

            HStack(spacing: 10) {
                SummaryPill(
                    title: "You owe",
                    value: formatCurrency(cents: youOweCents, currency: group.currency),
                    tint: .red600,
                    background: .red50
                )
                SummaryPill(
                    title: "You are owed",
                    value: formatCurrency(cents: youAreOwedCents, currency: group.currency),
                    tint: .green600,
                    background: .green.opacity(0.08)
                )
                SummaryPill(
                    title: "Settled",
                    value: isSettled ? "Yes" : "No",
                    tint: isSettled ? .green600 : .gray600,
                    background: .gray100
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private var directDebtsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)

            if directSuggestions.isEmpty {
                emptyCard(text: "No direct debts involving you.")
            } else {
                VStack(spacing: 10) {
                    ForEach(directSuggestions) { suggestion in
                        debtRow(suggestion: suggestion, showAction: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Transfers")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)

            if suggestions.isEmpty {
                emptyCard(text: "No transfer suggestions right now.")
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        debtRow(suggestion: suggestion, showAction: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settlement History")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray900)

            if paymentHistory.isEmpty {
                emptyCard(text: "No settlement payments yet.")
            } else {
                VStack(spacing: 10) {
                    ForEach(paymentHistory) { payment in
                        paymentRow(payment: payment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func debtRow(suggestion: SettlementSuggestion, showAction: Bool) -> some View {
        let fromName = membershipDisplayName(id: suggestion.fromMembership)
        let toName = membershipDisplayName(id: suggestion.toMembership)
        let amountText = formatCurrency(cents: suggestion.amountCents, currency: group.currency)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(fromName) -> \(toName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                    Text(amountText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray600)
                }
                Spacer()
            }

            if showAction, let membershipId = currentMembership?.id {
                if suggestion.fromMembership == membershipId {
                    actionButton(
                        title: "Mark as Paid",
                        style: .filled,
                        actionId: suggestion.id
                    ) {
                        await markAsPaid(suggestion: suggestion)
                    }
                } else if suggestion.toMembership == membershipId {
                    actionButton(
                        title: "Request Payment",
                        style: .outline,
                        actionId: suggestion.id
                    ) {
                        await requestPayment(suggestion: suggestion)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func paymentRow(payment: SettlementPayment) -> some View {
        let fromName = membershipDisplayName(id: payment.fromMembership)
        let toName = membershipDisplayName(id: payment.toMembership)
        let amountText = formatCurrency(cents: payment.amountCents, currency: group.currency)
        let isPending = payment.status.lowercased() == "pending"
        let canConfirm = isPending && payment.toMembership == currentMembership?.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(fromName) -> \(toName)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.gray900)
                    Text(amountText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray600)
                }
                Spacer()
                Text(payment.status.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isPending ? .blue700 : .green600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isPending ? Color.blue50 : Color.green.opacity(0.12))
                    .cornerRadius(999)
            }

            if canConfirm {
                actionButton(
                    title: "Confirm Payment",
                    style: .outline,
                    actionId: payment.id.uuidString
                ) {
                    await confirmPayment(paymentId: payment.id)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func emptyCard(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.gray600)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray200, lineWidth: 1)
            )
            .cornerRadius(12)
    }

    private enum ActionStyle {
        case filled
        case outline
    }

    private func actionButton(
        title: String,
        style: ActionStyle,
        actionId: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if inFlightActionIds.contains(actionId) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(style == .filled ? .white : .blue700)
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundColor(style == .filled ? .white : .blue700)
            .background(style == .filled ? Color.blue600 : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(style == .filled ? Color.clear : Color.blue200, lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .disabled(inFlightActionIds.contains(actionId))
    }

    private func membershipDisplayName(id: UUID) -> String {
        guard let membership = appState.membershipsByGroupId[group.id]?.first(where: { $0.id == id }) else {
            return String(id.uuidString.prefix(8))
        }

        if let user = membership.user {
            let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty {
                return fullName
            }
            return user.email
        }
        return membership.displayName
    }

    private func refreshData() async {
        do {
            async let membersTask: Void = appState.loadMembers(groupId: group.id)
            async let balancesTask: Void = appState.loadBalances(groupId: group.id)
            async let paymentsTask: Void = appState.loadSettlementPayments(groupId: group.id)
            _ = try await (membersTask, balancesTask, paymentsTask)
        } catch {
            errorMessage = "Failed to load balances and settlement data."
        }
    }

    private func markAsPaid(suggestion: SettlementSuggestion) async {
        let actionId = suggestion.id
        inFlightActionIds.insert(actionId)
        defer { inFlightActionIds.remove(actionId) }
        do {
            let request = SettlementPaymentCreateRequest(
                fromMembership: suggestion.fromMembership,
                toMembership: suggestion.toMembership,
                amountCents: suggestion.amountCents,
                autoConfirm: true
            )
            _ = try await appState.createSettlementPayment(groupId: group.id, request: request)
        } catch {
            errorMessage = "Failed to mark payment as paid."
        }
    }

    private func requestPayment(suggestion: SettlementSuggestion) async {
        let actionId = suggestion.id
        inFlightActionIds.insert(actionId)
        defer { inFlightActionIds.remove(actionId) }
        do {
            let request = SettlementPaymentCreateRequest(
                fromMembership: suggestion.fromMembership,
                toMembership: suggestion.toMembership,
                amountCents: suggestion.amountCents,
                note: "Requested from iOS",
                autoConfirm: false
            )
            _ = try await appState.createSettlementPayment(groupId: group.id, request: request)
        } catch {
            errorMessage = "Failed to request payment."
        }
    }

    private func confirmPayment(paymentId: UUID) async {
        let actionId = paymentId.uuidString
        inFlightActionIds.insert(actionId)
        defer { inFlightActionIds.remove(actionId) }
        do {
            _ = try await appState.confirmSettlementPayment(groupId: group.id, paymentId: paymentId)
        } catch {
            errorMessage = "Failed to confirm payment."
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let tint: Color
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray600)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(background)
        .cornerRadius(10)
    }
}
