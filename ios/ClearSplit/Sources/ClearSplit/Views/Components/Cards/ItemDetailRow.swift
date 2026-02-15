import SwiftUI

struct ItemDetailRow: View {
    let item: ShoppingItem
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.sm) {
                // Row 1: Name and Total
                HStack {
                    Text(item.name)
                        .font(ClearSplitTheme.Typography.bodyStrong)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                        .font(ClearSplitTheme.Typography.sectionTitle.weight(.bold))
                        .foregroundColor(.textPrimary)
                }

                // Row 2: Unit Price × Quantity
                if let unitPriceCents = item.unitPriceCents {
                    Text("\(formatCurrency(cents: unitPriceCents, currency: "USD")) × \(item.quantity)")
                        .font(ClearSplitTheme.Typography.subheadline)
                        .foregroundColor(.textTertiary)
                }

                // Row 3: Shared by
                VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.xs) {
                    Text("Shared by:")
                        .font(ClearSplitTheme.Typography.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)

                    // Participant Badges
                    HStack(spacing: 8) {
                        ForEach(sharedByMemberships) { membership in
                            ParticipantBadge(
                                membership: membership,
                                currentUserId: currentUserId
                            )
                        }
                    }
                }

                // Row 4: Your Share
                HStack {
                    Text("Your share:")
                        .font(ClearSplitTheme.Typography.subheadline)
                        .foregroundColor(.textSecondary)

                    Spacer()

                    Text(formatCurrency(cents: userShareCents, currency: "USD"))
                        .font(ClearSplitTheme.Typography.bodyStrong)
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(ClearSplitTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(Color.gray200, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var sharedByMemberships: [Membership] {
        let membershipIds = item.splits.map { $0.membershipId }
        return groupMemberships.filter { membershipIds.contains($0.id) }
    }

    private var userShareCents: Int {
        guard let currentUserId = currentUserId else { return 0 }

        guard let currentMembership = groupMemberships.first(where: { $0.user?.id == currentUserId }) else {
            return 0
        }

        if let split = item.splits.first(where: { $0.membershipId == currentMembership.id }) {
            return split.shareCents
        }

        return 0
    }
}
