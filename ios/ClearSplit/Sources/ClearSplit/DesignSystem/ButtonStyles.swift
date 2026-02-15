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
                    .fill(isEnabled ? Color.brandPrimary : Color.interactiveDisabled)
            )
            .applyElevation(isEnabled ? .medium : .none)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
                    .stroke(Color.borderMedium, lineWidth: ClearSplitTheme.Border.thin)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
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
                    .fill(tint.opacity(isEnabled ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearSplitTheme.Radius.md)
                    .stroke(tint.opacity(isEnabled ? 0.22 : 0.1), lineWidth: ClearSplitTheme.Border.thin)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
