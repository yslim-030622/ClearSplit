import SwiftUI

struct ParticipantBadge: View {
    let membership: Membership
    let currentUserId: UUID?

    var body: some View {
        Text(displayName)
            .font(ClearSplitTheme.Typography.caption.weight(.semibold))
            .foregroundColor(.brandPrimaryPressed)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.brandSubtle)
            .clipShape(Capsule())
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
