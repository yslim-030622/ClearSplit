import SwiftUI

// MARK: - Design Tokens

enum ClearSplitTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    enum Border {
        static let thin: CGFloat = 1
        static let focus: CGFloat = 2
    }

    struct Elevation {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let none = Elevation(color: .clear, radius: 0, x: 0, y: 0)
        static let low = Elevation(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        static let medium = Elevation(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        static let high = Elevation(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 4)
    }

    enum Typography {
        static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let sectionTitle = Font.system(.headline, design: .rounded)
        static let body = Font.system(.body, design: .rounded)
        static let bodyStrong = Font.system(.body, design: .rounded).weight(.semibold)
        static let subheadline = Font.system(.subheadline, design: .rounded)
        static let footnote = Font.system(.footnote, design: .rounded)
        static let caption = Font.system(.caption, design: .rounded)
    }
}

extension View {
    func applyElevation(_ elevation: ClearSplitTheme.Elevation) -> some View {
        shadow(color: elevation.color, radius: elevation.radius, x: elevation.x, y: elevation.y)
    }
}
