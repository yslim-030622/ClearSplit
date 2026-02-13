import SwiftUI

struct ParticipantAvatarView: View {
    let participant: ShoppingSessionParticipant
    let membership: Membership?
    let currentUserId: UUID?

    var body: some View {
        VStack(spacing: 6) {
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray700)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
        }
        .frame(width: 72)
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
            [Color(hex: "60A5FA"), Color(hex: "2563EB")], // Blue
            [Color(hex: "38BDF8"), Color(hex: "0284C7")], // Sky
            [Color(hex: "3B82F6"), Color(hex: "1D4ED8")], // Blue variant
            [Color(hex: "6366F1"), Color(hex: "4F46E5")], // Indigo
            [Color(hex: "8B5CF6"), Color(hex: "7C3AED")], // Purple
            [Color(hex: "EC4899"), Color(hex: "DB2777")], // Pink
            [Color(hex: "10B981"), Color(hex: "059669")], // Green
            [Color(hex: "F59E0B"), Color(hex: "D97706")]  // Amber
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
