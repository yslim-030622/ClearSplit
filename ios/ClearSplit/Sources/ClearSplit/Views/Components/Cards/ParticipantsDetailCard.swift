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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray700)

                    Text("Participants")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.gray900)
                }

                Spacer()

                // Count Badge
                Text("\(participants.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue700)
                    .frame(width: 24, height: 24)
                    .background(Color.blue50)
                    .clipShape(Circle())

                if canEdit, let onEditTapped {
                    Button(action: onEditTapped) {
                        Text(participants.isEmpty ? "Set" : "Edit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue600)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if participants.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No participants yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray700)

                    Text("Add members to this session to start splitting items.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.cardInset)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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
        .padding(20)
        .sectionStyle()
    }
}
