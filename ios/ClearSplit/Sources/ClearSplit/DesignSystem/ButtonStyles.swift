import SwiftUI

// MARK: - Button Styles

public struct ScaleButtonStyle: ButtonStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

public struct PrimaryActionButtonStyle: ButtonStyle {
    let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClearSplitTheme.Typography.bodyStrong)
            .foregroundColor(.textOnBrand)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .fill(isEnabled ? AnyShapeStyle(Color.brandGradient) : AnyShapeStyle(Color.interactiveDisabled))
            )
            .shadow(color: isEnabled ? Color.brandPrimary.opacity(0.15) : .clear, radius: 8, x: 0, y: 4)
            .shadow(color: Color.black.opacity(isEnabled ? 0.05 : 0), radius: 2, x: 0, y: 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct SecondaryActionButtonStyle: ButtonStyle {
    let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClearSplitTheme.Typography.bodyStrong)
            .foregroundColor(isEnabled ? .textPrimary : .textMuted)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(configuration.isPressed ? Color.borderStrong : Color.borderMedium, lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct TonalActionButtonStyle: ButtonStyle {
    let tint: Color
    let isEnabled: Bool

    public init(tint: Color = .brandPrimary, isEnabled: Bool = true) {
        self.tint = tint
        self.isEnabled = isEnabled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ClearSplitTheme.Typography.bodyStrong)
            .foregroundColor(isEnabled ? tint : .textMuted)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .fill(tint.opacity(isEnabled ? 0.08 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(tint.opacity(isEnabled ? 0.15 : 0.1), lineWidth: 0.75)
            )
            .brightness(configuration.isPressed ? -0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
