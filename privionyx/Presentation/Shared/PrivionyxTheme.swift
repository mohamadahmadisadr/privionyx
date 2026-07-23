import SwiftUI
import UIKit

enum PrivionyxTheme {
    enum Metrics {
        static let cardRadius: CGFloat = 20
        static let controlRadius: CGFloat = 16
        static let cardPadding: CGFloat = 18
        /// Small breathing room above the native tab bar. The system supplies the tab
        /// bar's own safe-area inset; this is just extra spacing below a screen's content.
        static let tabBarClearance: CGFloat = 12
    }

    enum Colors {
        static let background = dynamic(light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor(red: 0.039, green: 0.039, blue: 0.047, alpha: 1))
        static let backgroundSecondary = dynamic(light: UIColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1), dark: UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1))
        static let backgroundTertiary = dynamic(light: UIColor(red: 0.90, green: 0.93, blue: 0.99, alpha: 1), dark: UIColor(red: 0.031, green: 0.031, blue: 0.039, alpha: 1))
        static let surface = dynamic(light: .white, dark: UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1))
        static let surfaceStrong = dynamic(light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1))
        static let surfaceMuted = dynamic(light: UIColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1), dark: UIColor(red: 0.19, green: 0.20, blue: 0.24, alpha: 1))
        static let fieldBackground = dynamic(light: UIColor.black.withAlphaComponent(0.045), dark: UIColor.white.withAlphaComponent(0.08))
        static let fieldText = dynamic(light: UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1), dark: .white)
        /// The system accent — resolved from the AccentColor asset, or the OS default
        /// when that asset is empty. Never hardcode a brand blue over this; setting the
        /// asset should be the single knob that retints the whole app.
        static let accent = Color.accentColor
        static let accentStrong = Color.accentColor
        static let ink = dynamic(light: UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1), dark: .white)
        static let secondaryInk = dynamic(light: UIColor(red: 0.40, green: 0.44, blue: 0.50, alpha: 1), dark: UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.5))
        static let tertiaryInk = dynamic(light: UIColor(red: 0.52, green: 0.55, blue: 0.60, alpha: 1), dark: UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.4))
        static let separator = dynamic(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor.white.withAlphaComponent(0.06))
        static let glassStroke = dynamic(light: UIColor.black.withAlphaComponent(0.06), dark: UIColor.white.withAlphaComponent(0.08))
        static let success = dynamic(light: UIColor(red: 0.14, green: 0.55, blue: 0.34, alpha: 1), dark: UIColor(red: 0.33, green: 0.81, blue: 0.55, alpha: 1))
        static let warning = dynamic(light: UIColor(red: 0.85, green: 0.52, blue: 0.08, alpha: 1), dark: UIColor(red: 0.97, green: 0.73, blue: 0.28, alpha: 1))
        static let danger = dynamic(light: UIColor(red: 0.76, green: 0.25, blue: 0.24, alpha: 1), dark: UIColor(red: 0.98, green: 0.49, blue: 0.47, alpha: 1))

        /// Translucent panel fill used by every card, row group, and pill.
        static let glassFill = dynamic(light: UIColor.white.withAlphaComponent(0.72), dark: UIColor.white.withAlphaComponent(0.05))
        /// Slightly brighter fill for controls that sit on top of a glass panel.
        static let glassFillStrong = dynamic(light: UIColor.white.withAlphaComponent(0.9), dark: UIColor.white.withAlphaComponent(0.08))
        /// Accent wash behind icon tiles and badges.
        static let accentSoft = Color.accentColor.opacity(0.14)
        /// Unfilled portion of a progress bar.
        static let track = dynamic(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor(red: 0.11, green: 0.11, blue: 0.133, alpha: 1))
        /// Neutral avatar tile for merchants without an accent slot.
        static let neutralTile = dynamic(light: UIColor(red: 0.89, green: 0.90, blue: 0.93, alpha: 1), dark: UIColor(red: 0.165, green: 0.165, blue: 0.188, alpha: 1))
        /// The off-accent colour in alternating series (category bars, merchant tiles).
        static let mutedSeries = dynamic(light: UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1), dark: UIColor.white.withAlphaComponent(0.45))
        static let tabBarStroke = Color.accentColor.opacity(0.16)
        /// Foreground for content sitting on a filled accent surface. White rather than a
        /// tuned navy, because the accent is whatever the OS hands us.
        static let onAccent = Color.white
    }

    static let appBackground = LinearGradient(
        colors: [Colors.backgroundTertiary, Colors.background, Colors.backgroundSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

extension View {
    /// Translucent panel matching the prototype: soft fill, hairline stroke, no heavy shadow.
    func privionyxGlass(cornerRadius: CGFloat = PrivionyxTheme.Metrics.cardRadius, strong: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .background(strong ? PrivionyxTheme.Colors.glassFillStrong : PrivionyxTheme.Colors.glassFill, in: shape)
            .overlay(shape.stroke(PrivionyxTheme.Colors.glassStroke, lineWidth: 1))
    }

    func privionyxCardStyle(cornerRadius: CGFloat = PrivionyxTheme.Metrics.cardRadius) -> some View {
        self
            .padding(PrivionyxTheme.Metrics.cardPadding)
            .privionyxGlass(cornerRadius: cornerRadius)
    }
}
