import SwiftUI

struct AddItemParticipantRow: View {
    let participant: ShoppingSessionParticipant
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.clear : Color.gray300, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.blue600 : Color.white)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Name
                Text(displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray900)

                Spacer()
            }
            .frame(height: 56)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue50 : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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
            [Color(hex: "60A5FA"), Color(hex: "2563EB")], // Blue
            [Color(hex: "C084FC"), Color(hex: "9333EA")], // Purple
            [Color(hex: "4ADE80"), Color(hex: "16A34A")], // Green
            [Color(hex: "FB923C"), Color(hex: "EA580C")], // Orange
            [Color(hex: "F472B6"), Color(hex: "DB2777")], // Pink
            [Color(hex: "818CF8"), Color(hex: "4F46E5")]  // Indigo
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
