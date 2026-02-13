import SwiftUI

#if os(iOS)
import UIKit
#endif

extension Color {
    // MARK: - Enhanced Visibility Colors (BALANCED)

    /// Page background - lightest layer
    static let pageBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1.0) // #1C1C1E
                : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1.0) // #F2F2F7
        })
#else
        Color(red: 0.949, green: 0.949, blue: 0.969)
#endif
    }()

    /// Section background - middle layer
    static let sectionBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.153, green: 0.153, blue: 0.161, alpha: 1.0) // #272729
                : UIColor(red: 0.980, green: 0.980, blue: 0.988, alpha: 1.0) // #FAFAFC
        })
#else
        Color(red: 0.980, green: 0.980, blue: 0.988)
#endif
    }()

    /// Card background - top layer
    static let cardBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.192, green: 0.192, blue: 0.200, alpha: 1.0) // #313133
                : .white
        })
#else
        Color.white
#endif
    }()

    /// Inset background (for input fields, pills)
    static let cardInset: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.235, green: 0.235, blue: 0.243, alpha: 1.0) // #3C3C3E
                : UIColor(red: 0.969, green: 0.969, blue: 0.973, alpha: 1.0) // #F7F7F8
        })
#else
        Color(red: 0.969, green: 0.969, blue: 0.973)
#endif
    }()

    // MARK: - Borders

    /// Light border - subtle separation
    static let borderLight: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.290, green: 0.290, blue: 0.306, alpha: 1.0) // #4A4A4E
                : UIColor(red: 0.902, green: 0.902, blue: 0.922, alpha: 1.0) // #E6E6EB
        })
#else
        Color(red: 0.902, green: 0.902, blue: 0.922)
#endif
    }()

    /// Medium border - standard separation
    static let borderMedium: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.396, green: 0.396, blue: 0.412, alpha: 1.0) // #656569
                : UIColor(red: 0.851, green: 0.851, blue: 0.875, alpha: 1.0) // #D9D9DF
        })
#else
        Color(red: 0.851, green: 0.851, blue: 0.875)
#endif
    }()

    /// Strong border - emphasized separation
    static let borderStrong: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.529, green: 0.529, blue: 0.549, alpha: 1.0) // #87878C
                : UIColor(red: 0.780, green: 0.780, blue: 0.804, alpha: 1.0) // #C7C7CD
        })
#else
        Color(red: 0.780, green: 0.780, blue: 0.804)
#endif
    }()
}
