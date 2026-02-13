import SwiftUI

struct ParticipantPill: View {
    let title: String
    let isCurrentUser: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isCurrentUser ? .blue500 : .gray600)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .pillStyle(isCurrentUser: isCurrentUser)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(title) is sharing this item")
    }
}
