import SwiftUI

struct ItemsDetailCard: View {
    let items: [ShoppingItem]
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let onItemTap: (UUID) -> Void

    init(
        items: [ShoppingItem],
        participants: [ShoppingSessionParticipant],
        groupMemberships: [Membership] = [],
        currentUserId: UUID? = nil,
        onItemTap: @escaping (UUID) -> Void = { _ in }
    ) {
        self.items = items
        self.participants = participants
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
        self.onItemTap = onItemTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Items")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.gray900)

                Spacer()

                // Count Badge
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray700)
                    .frame(width: 24, height: 24)
                    .background(Color.gray100)
                    .clipShape(Circle())
            }

            // Items List
            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    ForEach(items) { item in
                        ItemDetailRow(
                            item: item,
                            participants: participants,
                            groupMemberships: groupMemberships,
                            currentUserId: currentUserId,
                            onTap: {
                                onItemTap(item.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray200, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
