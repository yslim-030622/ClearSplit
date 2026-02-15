import SwiftUI

struct ParticipantsDetailCard: View {
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?
    let canEdit: Bool
    let onEditTapped: (() -> Void)?

    private var participantGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 72), spacing: 12, alignment: .leading)]
    }

    init(
        participants: [ShoppingSessionParticipant],
        groupMemberships: [Membership] = [],
        currentUserId: UUID? = nil,
        canEdit: Bool = false,
        onEditTapped: (() -> Void)? = nil
    ) {
        self.participants = participants
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
        self.canEdit = canEdit
        self.onEditTapped = onEditTapped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.md) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.textSecondary)

                    Text("Participants")
                        .font(ClearSplitTheme.Typography.sectionTitle)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                // Count Badge
                Text("\(participants.count)")
                    .font(ClearSplitTheme.Typography.caption.weight(.semibold))
                    .foregroundColor(.brandPrimaryPressed)
                    .frame(width: 24, height: 24)
                    .background(Color.brandSubtle)
                    .clipShape(Circle())

                if canEdit, let onEditTapped {
                    Button(action: onEditTapped) {
                        Text(participants.isEmpty ? "Set" : "Edit")
                            .font(ClearSplitTheme.Typography.caption.weight(.semibold))
                            .foregroundColor(.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.brandSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if participants.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No participants yet")
                        .font(ClearSplitTheme.Typography.subheadline.weight(.medium))
                        .foregroundColor(.textSecondary)

                    Text("Add members to this session to start splitting items.")
                        .font(ClearSplitTheme.Typography.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.cardInset)
                .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                        .stroke(Color.borderLight, lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: participantGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(participants) { participant in
                        ParticipantAvatarView(
                            participant: participant,
                            membership: groupMemberships.first(where: { $0.id == participant.membershipId }),
                            currentUserId: currentUserId
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(ClearSplitTheme.Spacing.lg)
        .sectionStyle()
    }
}
