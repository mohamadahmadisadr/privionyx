import SwiftUI
import UIKit

enum PrivionyxTheme {
    enum Colors {
        static let background = dynamic(light: UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1), dark: UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1))
        static let backgroundSecondary = dynamic(light: UIColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1), dark: UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
        static let surface = dynamic(light: .white, dark: UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1))
        static let surfaceStrong = dynamic(light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1))
        static let surfaceMuted = dynamic(light: UIColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1), dark: UIColor(red: 0.19, green: 0.20, blue: 0.24, alpha: 1))
        static let fieldBackground = dynamic(light: UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), dark: UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1))
        static let fieldText = dynamic(light: UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1), dark: .white)
        static let accent = dynamic(light: UIColor(red: 0.08, green: 0.35, blue: 0.67, alpha: 1), dark: UIColor(red: 0.39, green: 0.67, blue: 0.95, alpha: 1))
        static let accentStrong = dynamic(light: UIColor(red: 0.07, green: 0.23, blue: 0.44, alpha: 1), dark: UIColor(red: 0.53, green: 0.76, blue: 0.97, alpha: 1))
        static let ink = dynamic(light: UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1), dark: UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
        static let secondaryInk = dynamic(light: UIColor(red: 0.39, green: 0.43, blue: 0.49, alpha: 1), dark: UIColor(red: 0.71, green: 0.75, blue: 0.80, alpha: 1))
        static let separator = dynamic(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.10))
        static let success = dynamic(light: UIColor(red: 0.14, green: 0.55, blue: 0.34, alpha: 1), dark: UIColor(red: 0.33, green: 0.81, blue: 0.55, alpha: 1))
        static let warning = dynamic(light: UIColor(red: 0.85, green: 0.52, blue: 0.08, alpha: 1), dark: UIColor(red: 0.97, green: 0.73, blue: 0.28, alpha: 1))
        static let danger = dynamic(light: UIColor(red: 0.76, green: 0.25, blue: 0.24, alpha: 1), dark: UIColor(red: 0.98, green: 0.49, blue: 0.47, alpha: 1))
    }

    static let appBackground = LinearGradient(
        colors: [Colors.background, Colors.backgroundSecondary],
        startPoint: .top,
        endPoint: .bottom
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
    func privionyxCardStyle() -> some View {
        self
            .padding(18)
            .background(PrivionyxTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PrivionyxTheme.Colors.separator, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}
