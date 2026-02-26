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
                ? UIColor(red: 0.078, green: 0.082, blue: 0.094, alpha: 1.0) // #141518
                : UIColor(red: 0.918, green: 0.925, blue: 0.961, alpha: 1.0) // #EAECF5
        })
#else
        Color(red: 0.918, green: 0.925, blue: 0.961)
#endif
    }()

    /// Section background - middle layer
    static let sectionBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.114, green: 0.122, blue: 0.141, alpha: 1.0) // #1D1F24
                : UIColor(red: 0.941, green: 0.945, blue: 0.973, alpha: 1.0) // #F0F1F8
        })
#else
        Color(red: 0.941, green: 0.945, blue: 0.973)
#endif
    }()

    /// Card background - top layer
    static let cardBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.145, green: 0.157, blue: 0.188, alpha: 1.0) // #252830
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
                ? UIColor(red: 0.180, green: 0.188, blue: 0.224, alpha: 1.0) // #2E3039
                : UIColor(red: 0.945, green: 0.949, blue: 0.969, alpha: 1.0) // #F1F2F7
        })
#else
        Color(red: 0.945, green: 0.949, blue: 0.969)
#endif
    }()

    // MARK: - Borders

    /// Light border - subtle separation
    static let borderLight: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.208, green: 0.220, blue: 0.259, alpha: 1.0) // #353842
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
                ? UIColor(red: 0.282, green: 0.302, blue: 0.353, alpha: 1.0) // #484D5A
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
                ? UIColor(red: 0.420, green: 0.439, blue: 0.502, alpha: 1.0) // #6B7080
                : UIColor(red: 0.780, green: 0.780, blue: 0.804, alpha: 1.0) // #C7C7CD
        })
#else
        Color(red: 0.780, green: 0.780, blue: 0.804)
#endif
    }()

    // MARK: - Additional Surfaces

    /// Elevated Card Background (for sheets/modals)
    static let elevatedCardBackground: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.169, green: 0.180, blue: 0.212, alpha: 1.0) // #2B2E36 (brighter than card)
                : .white
        })
#else
        Color.white
#endif
    }()

    /// Subtle Border - ultra-light separation
    static let borderSubtle: Color = {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.165, green: 0.176, blue: 0.208, alpha: 1.0) // #2A2D35
                : UIColor(red: 0.941, green: 0.945, blue: 0.961, alpha: 1.0) // #F0F1F5
        })
#else
        Color(red: 0.941, green: 0.945, blue: 0.961)
#endif
    }()
}
