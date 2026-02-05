import SwiftUI

// MARK: - Design System Colors

public extension Color {
    static let blue600 = Color(hex: "2563EB")
    static let blue700 = Color(hex: "1D4ED8")
    static let blue500 = Color(hex: "3B82F6")
    static let blue400 = Color(hex: "60A5FA")
    static let blue200 = Color(hex: "BFDBFE")
    static let blue100 = Color(hex: "DBEAFE")
    static let blue50 = Color(hex: "EFF6FF")
    static let blue800 = Color(hex: "1E40AF")
    static let blue900 = Color(hex: "1E3A8A")
    static let green600 = Color(hex: "16A34A")
    static let gray800 = Color(hex: "1F2937")
    static let gray900 = Color(hex: "111827")
    static let gray700 = Color(hex: "374151")
    static let gray600 = Color(hex: "4B5563")
    static let gray500 = Color(hex: "6B7280")
    static let gray400 = Color(hex: "9CA3AF")
    static let gray300 = Color(hex: "D1D5DB")
    static let gray200 = Color(hex: "E5E7EB")
    static let gray100 = Color(hex: "F3F4F6")
    static let gray50 = Color(hex: "F9FAFB")
    static let red500 = Color(hex: "EF4444")
    static let red600 = Color(hex: "DC2626")
    static let red50 = Color(hex: "FEF2F2")
    static let red300 = Color(hex: "FCA5A5")
    
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
