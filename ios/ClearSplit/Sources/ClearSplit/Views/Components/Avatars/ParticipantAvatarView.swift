import SwiftUI

struct ParticipantAvatarView: View {
    let participant: ShoppingSessionParticipant
    let membership: Membership?
    let currentUserId: UUID?

    var body: some View {
        VStack(spacing: ClearSplitTheme.Spacing.xs - 2) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 40, height: 40)

                Text(displayInitial)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            // Name
            Text(displayName)
                .font(ClearSplitTheme.Typography.caption.weight(.medium))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var displayName: String {
        if let membership = membership,
           let user = membership.user {
            if user.id == currentUserId {
                return "You"
            }
            let fullName = "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty {
                return fullName
            }
            return user.displayName
        }
        return "Member \(participant.membershipId.uuidString.prefix(4).uppercased())"
    }

    private var displayInitial: String {
        if let membership = membership,
           let user = membership.user {
            return String(user.firstName.prefix(1)).uppercased()
        }
        return String(participant.membershipId.uuidString.prefix(1)).uppercased()
    }

    private var avatarGradient: LinearGradient {
        let colors = [
            [Color(hex: "60A5FA"), Color(hex: "2563EB")],
            [Color(hex: "38BDF8"), Color(hex: "0284C7")],
            [Color(hex: "14B8A6"), Color(hex: "0F766E")],
            [Color(hex: "10B981"), Color(hex: "059669")],
            [Color(hex: "64748B"), Color(hex: "334155")],
            [Color(hex: "0EA5E9"), Color(hex: "0369A1")]
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
