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
                        isHovered ? Color.borderMedium : Color.borderLight,
                        lineWidth: 0.5
                    )
            )
            // Multi-layer shadow
            .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 4, x: 0, y: isHovered ? 6 : 2)
            .shadow(color: Color.black.opacity(isHovered ? 0.04 : 0.02), radius: isHovered ? 4 : 1, x: 0, y: 1)
            // Hover ambient layer
            .shadow(color: isHovered ? Color.brandPrimary.opacity(0.05) : Color.clear, radius: 20, x: 0, y: 8)
    }
}

// MARK: - Section Style Modifier
struct SectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.lg)
                    .stroke(Color.borderLight, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.02), radius: 1, x: 0, y: 1)
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
                        isHovered ? Color.borderMedium : Color.borderLight,
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0.03), radius: isHovered ? 8 : 2, x: 0, y: isHovered ? 4 : 1)
            .shadow(color: Color.black.opacity(isHovered ? 0.03 : 0.01), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Pill Style (for participant tags)
struct PillStyle: ViewModifier {
    var isCurrentUser: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isCurrentUser
                    ? Color.brandPrimary.opacity(0.10)
                    : Color.cardInset
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.sm)
                    .stroke(Color.borderSubtle, lineWidth: 0.5)
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
                    .stroke(borderColor, lineWidth: isFocused || hasError ? 1.5 : 0.5)
            )
            // Outer glow focus ring
            .shadow(color: isFocused && !hasError ? Color.brandFocusRing : Color.clear, radius: 4, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }

    private var borderColor: Color {
        if hasError {
            return .red300
        }
        return isFocused ? .brandPrimary : .borderLight
    }
}

// MARK: - Staggered Appearance Modifier
struct StaggeredAppearance: ViewModifier {
    let index: Int
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Animating Currency Text
struct AnimatingCurrencyText: View {
    let value: Int
    let currency: String
    let font: Font
    let tracking: CGFloat
    let color: Color
    
    @State private var animatedValue: Int = 0
    
    var body: some View {
        Text(formatCurrency(cents: animatedValue, currency: currency))
            .font(font)
            .tracking(tracking)
            .foregroundColor(color)
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animatedValue = value
                }
            }
            .onChange(of: value) { newValue in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    animatedValue = newValue
                }
            }
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
    
    func staggeredAppearance(index: Int) -> some View {
        modifier(StaggeredAppearance(index: index))
    }
}
