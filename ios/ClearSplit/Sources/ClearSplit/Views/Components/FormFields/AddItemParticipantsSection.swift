import SwiftUI

struct AddItemParticipantsSection: View {
    let participants: [ShoppingSessionParticipant]
    @Binding var selectedParticipants: Set<UUID>
    var formErrors: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("Who will share this item?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.gray900)
                Text("*")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red500)
            }

            if let error = formErrors["participants"] {
                Text(error)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.red600)
            } else {
                Text("Select at least one person")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray500)
            }

            VStack(spacing: 8) {
                ForEach(participants) { participant in
                    AddItemParticipantRow(
                        participant: participant,
                        isSelected: selectedParticipants.contains(participant.membershipId),
                        onToggle: {
                            if selectedParticipants.contains(participant.membershipId) {
                                selectedParticipants.remove(participant.membershipId)
                            } else {
                                selectedParticipants.insert(participant.membershipId)
                            }
                        }
                    )
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(formErrors["participants"] != nil ? Color.red300 : Color.gray200, lineWidth: 1)
        )
    }
}
