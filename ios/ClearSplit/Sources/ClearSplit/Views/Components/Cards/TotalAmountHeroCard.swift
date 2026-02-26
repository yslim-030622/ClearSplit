import SwiftUI

struct TotalAmountHeroCard: View {
    let totalCents: Int
    let paidByMembershipId: UUID
    let groupMemberships: [Membership]
    let currentUserId: UUID?

    init(
        totalCents: Int,
        paidByMembershipId: UUID,
        groupMemberships: [Membership] = [],
        currentUserId: UUID? = nil
    ) {
        self.totalCents = totalCents
        self.paidByMembershipId = paidByMembershipId
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label
            Text("Total Amount")
                .font(ClearSplitTheme.Typography.overline)
                .textCase(.uppercase)
                .tracking(ClearSplitTheme.Tracking.extraWide)
                .foregroundColor(.white.opacity(0.9))
                .padding(.bottom, 8)

            // Amount
            AnimatingCurrencyText(
                value: totalCents,
                currency: "USD",
                font: ClearSplitTheme.Typography.currencyHero,
                tracking: ClearSplitTheme.Tracking.tight,
                color: .white
            )
                .padding(.bottom, 12)

            // Paid by
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))

                Text(paidByText)
                    .font(ClearSplitTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ClearSplitTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.brandPrimary, Color.brandPrimaryPressed],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(20)
        .shadow(color: Color.blue600.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    private var paidByText: String {
        guard let membership = groupMemberships.first(where: { $0.id == paidByMembershipId }) else {
            return "Paid by Unknown"
        }

        guard let user = membership.user else {
            return "Paid by \(membership.displayName)"
        }

        if user.id == currentUserId {
            return "Paid by You"
        }

        return "Paid by \(user.displayName)"
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
