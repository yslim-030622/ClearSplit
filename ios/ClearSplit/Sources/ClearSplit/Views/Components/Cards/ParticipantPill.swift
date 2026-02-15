import SwiftUI

struct ParticipantPill: View {
    let title: String
    let isCurrentUser: Bool

    var body: some View {
        Text(title)
            .font(ClearSplitTheme.Typography.caption.weight(.semibold))
            .foregroundColor(isCurrentUser ? .brandPrimary : .textSecondary)
            .padding(.horizontal, ClearSplitTheme.Spacing.sm)
            .padding(.vertical, ClearSplitTheme.Spacing.xs - 1)
            .pillStyle(isCurrentUser: isCurrentUser)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm))
            .accessibilityLabel("\(title) is sharing this item")
    }
}
