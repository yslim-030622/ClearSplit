import SwiftUI

struct ItemDetailRow: View {
    let item: ShoppingItem
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Row 1: Name and Total
                HStack {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)

                    Spacer()

                    Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.gray900)
                }

                // Row 2: Unit Price × Quantity
                if let unitPriceCents = item.unitPriceCents {
                    Text("\(formatCurrency(cents: unitPriceCents, currency: "USD")) × \(item.quantity)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray500)
                }

                // Row 3: Shared by
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared by:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray600)

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
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.gray600)

                    Spacer()

                    Text(formatCurrency(cents: userShareCents, currency: "USD"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray900)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray50)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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
