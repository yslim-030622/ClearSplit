import SwiftUI

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Color.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isHovered ? Color.borderStrong : Color.borderMedium,
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.08 : 0.05),
                radius: isHovered ? 8 : 4,
                x: 0,
                y: isHovered ? 3 : 2
            )
    }
}

// MARK: - Section Style Modifier
struct SectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.sectionBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.borderMedium, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.05),
                radius: 4,
                x: 0,
                y: 2
            )
    }
}

// MARK: - Item Card Style (for lists)
struct ItemCardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Color.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? Color.borderStrong : Color.borderMedium,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.08 : 0.04),
                radius: isHovered ? 6 : 3,
                x: 0,
                y: isHovered ? 2 : 1
            )
    }
}

// MARK: - Pill Style (for participant tags)
struct PillStyle: ViewModifier {
    var isCurrentUser: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isCurrentUser
                    ? Color(red: 0.231, green: 0.510, blue: 0.965).opacity(0.1)
                    : Color.cardInset
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
    }
}

// MARK: - View Extension for Easy Usage
extension View {
    func cardStyle(isHovered: Bool = false) -> some View {
        modifier(CardStyle(isHovered: isHovered))
    }

    func sectionStyle() -> some View {
        modifier(SectionStyle())
    }

    func itemCardStyle(isHovered: Bool = false) -> some View {
        modifier(ItemCardStyle(isHovered: isHovered))
    }

    func pillStyle(isCurrentUser: Bool = false) -> some View {
        modifier(PillStyle(isCurrentUser: isCurrentUser))
    }
}
