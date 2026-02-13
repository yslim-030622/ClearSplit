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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(item.quantity) \(item.name)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray900)
                    .lineLimit(2)

                Spacer()

                Text(formatCurrency(cents: item.totalCents, currency: "USD"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("Shared by:")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray600)

                Text(sharedByText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray400)
                    .lineLimit(1)
            }

            HStack {
                Text("Your share:")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray600)

                Spacer()

                Text(formatCurrency(cents: yourShareCents, currency: "USD"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
            }
        }
        .padding(16)
        .itemCardStyle(isHovered: isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
