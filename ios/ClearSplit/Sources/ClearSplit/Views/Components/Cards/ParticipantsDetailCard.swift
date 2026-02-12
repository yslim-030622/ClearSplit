import SwiftUI

struct ParticipantsDetailCard: View {
    let participants: [ShoppingSessionParticipant]
    let groupMemberships: [Membership]
    let currentUserId: UUID?

    init(
        participants: [ShoppingSessionParticipant],
        groupMemberships: [Membership] = [],
        currentUserId: UUID? = nil
    ) {
        self.participants = participants
        self.groupMemberships = groupMemberships
        self.currentUserId = currentUserId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
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
            }

            // Participants List
            HStack(spacing: 16) {
                ForEach(participants) { participant in
                    ParticipantAvatarView(
                        participant: participant,
                        membership: groupMemberships.first(where: { $0.id == participant.membershipId }),
                        currentUserId: currentUserId
                    )
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
