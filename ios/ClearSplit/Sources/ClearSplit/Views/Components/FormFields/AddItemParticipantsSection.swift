import SwiftUI

struct AddItemParticipantsSection: View {
    let participants: [ShoppingSessionParticipant]
    @Binding var selectedParticipants: Set<UUID>
    var formErrors: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: ClearSplitTheme.Spacing.sm) {
            HStack(spacing: 4) {
                Text("Who will share this item?")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.textPrimary)
                Text("*")
                    .font(ClearSplitTheme.Typography.bodyStrong)
                    .foregroundColor(.danger)
            }

            if let error = formErrors["participants"] {
                Text(error)
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.danger)
            } else {
                Text("Select at least one person")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
            }

            if participants.isEmpty {
                Text("No participants available for this session.")
                    .font(ClearSplitTheme.Typography.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.cardInset)
                    .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm)
                            .stroke(Color.borderLight, lineWidth: 1)
                    )
            } else {
                VStack(spacing: ClearSplitTheme.Spacing.xs) {
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
        }
        .padding(ClearSplitTheme.Spacing.lg)
        .background(Color.sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                .stroke(formErrors["participants"] != nil ? Color.red300 : Color.borderMedium, lineWidth: 1)
        )
        .applyElevation(.low)
    }
}
