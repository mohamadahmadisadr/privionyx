import SwiftUI
import Foundation
import UIKit

struct PrivionyxScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let scrollContent: Bool
    let dismissKeyboardOnTap: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        scrollContent: Bool = true,
        dismissKeyboardOnTap: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.scrollContent = scrollContent
        self.dismissKeyboardOnTap = dismissKeyboardOnTap
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PrivionyxTheme.appBackground
                    .ignoresSafeArea()

                if scrollContent {
                    ScrollView(showsIndicators: false) {
                        screenContent
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard dismissKeyboardOnTap else { return }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                } else {
                    screenContent
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var screenContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScreenHeader(title: title, subtitle: subtitle)
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            HStack(alignment: .bottom) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer()

                Image(systemName: icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(detail)
                .font(.footnote)
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privionyxCardStyle()
    }
}

struct SectionHeader: View {
    let title: String
    let actionTitle: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Spacer()

            if let actionTitle {
                Text(actionTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
            }
        }
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .frame(width: 44, height: 44)
                .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(PrivionyxTheme.Colors.accentStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(PrivionyxTheme.Colors.ink)
            .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PrivionyxTheme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct InfoPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum PrivionyxCurrencyFormatter {
    static var currentCurrencyCode: String {
        Locale.autoupdatingCurrent.currency?.identifier ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func string(for amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.numberStyle = .currencyISOCode
        formatter.currencyCode = currentCurrencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(from: NSNumber(value: amount))
            ?? amount.formatted(.currency(code: currentCurrencyCode).presentation(.isoCode))
    }
}
