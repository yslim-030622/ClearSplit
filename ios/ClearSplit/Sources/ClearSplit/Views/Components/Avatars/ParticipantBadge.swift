import SwiftUI

struct ParticipantBadge: View {
    let membership: Membership
    let currentUserId: UUID?

    var body: some View {
        Text(displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.blue700)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.blue50)
            .cornerRadius(14)
    }

    private var displayName: String {
        if let user = membership.user {
            if user.id == currentUserId {
                return "You"
            }
            return "\(user.firstName) \(user.lastName)"
        }
        return "Member"
    }
}
