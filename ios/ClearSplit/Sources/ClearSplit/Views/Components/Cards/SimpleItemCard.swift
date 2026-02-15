import SwiftUI

struct SimpleItemCard: View {
    let item: ShoppingItem
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    @State private var isHovered = false

    private var currentMembershipId: UUID? {
        groupMemberships.first(where: { $0.user?.id == currentUserId })?.id
    }

    private var yourShareCents: Int {
        guard let currentMembershipId else { return 0 }
        return item.splits.first(where: { $0.membershipId == currentMembershipId })?.shareCents ?? 0
    }

    private var sharedByText: String {
        guard !item.splits.isEmpty else { return "—" }

        let names: [String] = item.splits.map { split in
            if split.membershipId == currentMembershipId {
                return "You"
            }

            if let membership = groupMemberships.first(where: { $0.id == split.membershipId }),
               let user = membership.user {
                let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
                return fullName.isEmpty ? user.displayName : fullName
            }

            return "Member \(split.membershipId.uuidString.prefix(4).uppercased())"
        }

        return names.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.xs + 2) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(item.quantity) \(item.name)")
                    .font(ClearSplitTheme.Typography.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Spacer()

                Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("Shared by:")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textSecondary)

                Text(sharedByText)
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
            }

            HStack {
                Text("Your share:")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textSecondary)

                Spacer()

                Text(formatCurrency(cents: yourShareCents, currency: "USD"))
                    .font(ClearSplitTheme.Typography.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(ClearSplitTheme.Spacing.md)
        .itemCardStyle(isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
