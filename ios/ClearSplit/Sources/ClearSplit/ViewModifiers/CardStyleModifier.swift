import SwiftUI

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                    .stroke(
                        isHovered ? Color.borderStrong : Color.borderMedium,
                        lineWidth: isHovered ? 1.5 : 1
                    )
            )
            .applyElevation(isHovered ? .high : .low)
    }
}

// MARK: - Section Style Modifier
struct SectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.sectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                    .stroke(Color.borderMedium, lineWidth: 1)
            )
            .applyElevation(.low)
    }
}

// MARK: - Item Card Style (for lists)
struct ItemCardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(
                        isHovered ? Color.borderStrong : Color.borderMedium,
                        lineWidth: 1
                    )
            )
            .applyElevation(isHovered ? .medium : .low)
    }
}

// MARK: - Pill Style (for participant tags)
struct PillStyle: ViewModifier {
    var isCurrentUser: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isCurrentUser
                    ? Color.brandPrimary.opacity(0.12)
                    : Color.cardInset
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm)
                    .stroke(Color.borderLight, lineWidth: 1)
            )
    }
}

// MARK: - Input Field Style
struct AppInputFieldStyle: ViewModifier {
    var isFocused: Bool
    var hasError: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(hasError ? Color.dangerSurface : (isFocused ? Color.cardBackground : Color.cardInset))
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(borderColor, lineWidth: isFocused || hasError ? ClearSplitTheme.Border.focus : ClearSplitTheme.Border.thin)
            )
    }

    private var borderColor: Color {
        if hasError {
            return .red300
        }
        return isFocused ? .brandPrimary : .borderLight
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

    func appInputFieldStyle(isFocused: Bool = false, hasError: Bool = false) -> some View {
        modifier(AppInputFieldStyle(isFocused: isFocused, hasError: hasError))
    }
}
