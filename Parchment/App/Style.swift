import SwiftUI
import UIKit

/// Parchment's MyScript/Nebo-style design tokens, kept in one place.
enum Style {
    /// Brand accent: MyScript active blue (selected tools, confirm buttons).
    static let accent = Color(hex: "0A60FF")
    static let selection = Color(hex: "007AFF")

    static let cardRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10

    /// Smooth spring used for modal switches and card selections.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// Light tap for tool picks, recognized gestures and cover switches.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

extension UIColor {
    /// Warm off-white page (never harsh pure white).
    static let paper = UIColor(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xF5 / 255, alpha: 1)
    /// MyScript's soft slate-blue rules and dots.
    static let paperLine = UIColor(red: 90 / 255, green: 115 / 255, blue: 150 / 255, alpha: 0.28)
    /// Neutral slate app chrome.
    static let chrome = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1C / 255, green: 0x1D / 255, blue: 0x21 / 255, alpha: 1)
            : UIColor(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF7 / 255, alpha: 1)
    }
    /// Ultra-thin dividers.
    static let hairline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(red: 0xE2 / 255, green: 0xE4 / 255, blue: 0xEB / 255, alpha: 1)
    }
}

extension Color {
    static let paper = Color(uiColor: .paper)
    static let chrome = Color(uiColor: .chrome)
    static let hairline = Color(uiColor: .hairline)
}

extension View {
    /// Soft, diffused card elevation.
    func ambientShadow() -> some View {
        shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }

    /// Wide sheets (the two-pane New Notebook, the cover studio) on iPad.
    @ViewBuilder
    func wideSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page).presentationCornerRadius(Style.sheetRadius)
        } else {
            presentationDetents([.large]).presentationCornerRadius(Style.sheetRadius)
        }
    }
}
