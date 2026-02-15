import SwiftUI

struct AddItemParticipantRow: View {
    let participant: ShoppingSessionParticipant
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: ClearSplitTheme.Spacing.sm) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.brandPrimary : Color.cardBackground)
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Avatar
                ZStack {
                    Circle()
                        .fill(avatarGradient)
                        .frame(width: 32, height: 32)

                    Text(displayInitial)
                        .font(ClearSplitTheme.Typography.caption.weight(.semibold))
                        .foregroundColor(.textOnBrand)
                }

                // Name
                Text(displayName)
                    .font(ClearSplitTheme.Typography.body)
                    .foregroundColor(.textPrimary)

                Spacer()
            }
            .frame(height: 56)
            .padding(.horizontal, ClearSplitTheme.Spacing.sm)
            .background(isSelected ? Color.brandSubtle : Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(isSelected ? Color.blue200 : Color.gray200, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var displayName: String {
        "Member \(participant.membershipId.uuidString.prefix(4).uppercased())"
    }

    private var displayInitial: String {
        let idString = participant.membershipId.uuidString.uppercased()
        return String(idString.prefix(1))
    }

    private var avatarGradient: LinearGradient {
        let colors = [
            [Color(hex: "60A5FA"), Color(hex: "2563EB")],
            [Color(hex: "38BDF8"), Color(hex: "0284C7")],
            [Color(hex: "4ADE80"), Color(hex: "16A34A")],
            [Color(hex: "14B8A6"), Color(hex: "0F766E")],
            [Color(hex: "818CF8"), Color(hex: "4F46E5")],
            [Color(hex: "64748B"), Color(hex: "334155")]
        ]

        let hash = participant.membershipId.uuidString.hashValue
        let index = abs(hash) % colors.count
        let colorPair = colors[index]

        return LinearGradient(
            colors: colorPair,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
