import SwiftUI

// MARK: - Design System Colors

public extension Color {
    // MARK: Palette
    static let blue600 = Color(hex: "1E56E8")
    static let blue700 = Color(hex: "1847D0")
    static let blue500 = Color(hex: "3672F0")
    static let blue400 = Color(hex: "5B8DF8")
    static let blue200 = Color(hex: "BAD0FE")
    static let blue100 = Color(hex: "DBE4FF")
    static let blue50 = Color(hex: "EEF2FF")
    static let blue800 = Color(hex: "183BA8")
    static let blue900 = Color(hex: "162E7A")
    static let green600 = Color(hex: "129645")
    static let gray800 = Color(hex: "1C2A38")
    static let gray900 = Color(hex: "0F1A28")
    static let gray700 = Color(hex: "32404F")
    static let gray600 = Color(hex: "454F60")
    static let gray500 = Color(hex: "636D80")
    static let gray400 = Color(hex: "949BAC")
    static let gray300 = Color(hex: "CDD2DE")
    static let gray200 = Color(hex: "E2E5EE")
    static let gray100 = Color(hex: "F1F3F8")
    static let gray50 = Color(hex: "F8F9FC")
    static let red500 = Color(hex: "E8413E")
    static let red600 = Color(hex: "D42424")
    static let red50 = Color(hex: "FEF2F2")
    static let red300 = Color(hex: "FCA5A5")
    static let amber600 = Color(hex: "C96F05")
    static let amber100 = Color(hex: "FEF3C7")
    static let green500 = Color(hex: "0EA67A")
    static let green100 = Color(hex: "D1FAE5")

    // MARK: Semantic
    static let brandPrimary = Color.blue600
    static let brandPrimaryPressed = Color.blue700
    static let brandSubtle = Color.blue50
    static let brandSurface = Color.blue100

    static let textPrimary = Color.gray900
    static let textSecondary = Color.gray700
    static let textTertiary = Color.gray500
    static let textMuted = Color.gray400
    static let textOnBrand = Color.white

    static let success = Color.green600
    static let successSurface = Color.green100
    static let warning = Color.amber600
    static let warningSurface = Color.amber100
    static let danger = Color.red600
    static let dangerSurface = Color.red50

    static let interactiveDisabled = Color.gray300
    static let overlayScrim = Color.black.opacity(0.45)

    static let infoSurface = Color.blue100
    static let infoBorder = Color.blue200
    

    // MARK: - Gradients
    static let brandGradient = LinearGradient(colors: [.blue500, .blue700], startPoint: .top, endPoint: .bottom)
    static let heroCardGradient = LinearGradient(colors: [.blue600, Color(hex: "162E7A")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let successGradient = LinearGradient(colors: [.green500, .green600], startPoint: .top, endPoint: .bottom)

    // MARK: - Accents
    static let brandAccentLight = Color.blue400.opacity(0.15)
    static let brandFocusRing = Color.blue400.opacity(0.25)

    // MARK: - Semantic (Additional)
    static let settledSurface = Color(hex: "ECFDF5") // green50 roughly
    static let settledBorder = Color(hex: "A7F3D0") // green200
    static let settledText = Color(hex: "047857") // green700
    static let settledHeading = Color(hex: "065F46") // green800
    static let warningHeading = Color(hex: "B45309") // amber700
    static let warningText = Color.amber600
    static let warningBorder = Color(hex: "FDE68A") // amber200
    static let dangerHeading = Color(hex: "B91C1C") // red700
    static let infoText = Color.blue800
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
