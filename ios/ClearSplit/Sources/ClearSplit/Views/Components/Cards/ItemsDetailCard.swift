import SwiftUI

struct ItemsDetailCard: View {
    enum DisplayMode {
        case detailed
        case simple
    }

    let items: [ShoppingItem]
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let displayMode: DisplayMode
    let onAddItem: () -> Void
    let onSaveItem: (ShoppingItem, ShoppingItemCreate, [UUID]) async -> String?
    let onDeleteItem: (UUID) -> Void
    let onItemTap: (UUID) -> Void

    init(
        items: [ShoppingItem],
        participants: [ShoppingSessionParticipant],
        groupMemberships: [Membership] = [],
        currentUserId: UUID? = nil,
        displayMode: DisplayMode = .detailed,
        onAddItem: @escaping () -> Void = {},
        onSaveItem: @escaping (ShoppingItem, ShoppingItemCreate, [UUID]) async -> String? = { _, _, _ in nil },
        onDeleteItem: @escaping (UUID) -> Void = { _ in },
        onItemTap: @escaping (UUID) -> Void = { _ in }
    ) {
        self.items = items
        self.participants = participants
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
        self.displayMode = displayMode
        self.onAddItem = onAddItem
        self.onSaveItem = onSaveItem
        self.onDeleteItem = onDeleteItem
        self.onItemTap = onItemTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if items.isEmpty {
                Text("No items yet")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .itemCardStyle()
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        switch displayMode {
                        case .detailed:
                            DetailedItemCard(
                                item: item,
                                participantMembershipIds: participants.map { $0.membershipId },
                                groupMemberships: groupMemberships,
                                currentUserId: currentUserId,
                                onSaveEdit: onSaveItem,
                                onDelete: { onDeleteItem(item.id) }
                            )
                        case .simple:
                            Button(action: { onItemTap(item.id) }) {
                                SimpleItemCard(
                                    item: item,
                                    groupMemberships: groupMemberships,
                                    currentUserId: currentUserId
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if displayMode == .detailed {
                addItemButton
            }
        }
        .sectionStyle()
    }

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            Text("Items")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.gray900)

            Spacer()

            Text("\(items.count)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray600)
                .frame(minWidth: 24, minHeight: 24)
                .padding(.horizontal, 6)
                .background(Color.gray100)
                .clipShape(Circle())
        }
        .padding(.bottom, 4)
    }

    private var addItemButton: some View {
        Button(action: onAddItem) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))

                Text("Add Item")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.blue500)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Add item")
    }
}
