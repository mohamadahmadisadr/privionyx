import SwiftUI
import UIKit

// MARK: - Screen scaffold

/// Standard screen: gradient ground, large title, scrolling body, and enough bottom
/// room to clear the floating tab bar.
struct GlassScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    var scrollContent: Bool = true
    /// Builds the content in a `LazyVStack` so rows are created as they scroll into view.
    /// Off by default — laziness costs SwiftUI the ability to size the whole stack up front,
    /// which is only worth paying on a screen whose content grows without bound.
    var lazyContent: Bool = false
    var dismissKeyboardOnTap: Bool = true
    /// Tab roots own a navigation stack; screens pushed onto an existing stack must not
    /// create a nested one, or their own pushes lose the back gesture.
    var wrapsInNavigationStack: Bool = true
    /// Replaces the default title block — used where a screen needs controls in the header.
    var header: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        scrollContent: Bool = true,
        dismissKeyboardOnTap: Bool = true,
        wrapsInNavigationStack: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.scrollContent = scrollContent
        self.dismissKeyboardOnTap = dismissKeyboardOnTap
        self.wrapsInNavigationStack = wrapsInNavigationStack
        self.header = nil
        self.content = content()
    }

    init<Header: View>(
        scrollContent: Bool = true,
        lazyContent: Bool = false,
        dismissKeyboardOnTap: Bool = true,
        wrapsInNavigationStack: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.title = ""
        self.subtitle = nil
        self.scrollContent = scrollContent
        self.lazyContent = lazyContent
        self.dismissKeyboardOnTap = dismissKeyboardOnTap
        self.wrapsInNavigationStack = wrapsInNavigationStack
        self.header = AnyView(header())
        self.content = content()
    }

    var body: some View {
        if wrapsInNavigationStack {
            NavigationStack { screenBody }
        } else {
            screenBody
        }
    }

    private var screenBody: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

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

    @ViewBuilder
    private var screenContent: some View {
        if lazyContent {
            LazyVStack(alignment: .leading, spacing: 20) { stackContent }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, PrivionyxTheme.Metrics.tabBarClearance)
        } else {
            VStack(alignment: .leading, spacing: 20) { stackContent }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, PrivionyxTheme.Metrics.tabBarClearance)
        }
    }

    /// Left unwrapped — no enclosing `Group` or `VStack` — so `LazyVStack` sees the header
    /// and the content as separate children and can defer the ones off screen.
    @ViewBuilder
    private var stackContent: some View {
        if let header {
            header
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        content
    }
}

// MARK: - Layout primitives

/// Section label used above grouped content ("Spending by Category", "Recent Receipts").
struct GlassSectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Spacer(minLength: 12)

            if let actionTitle {
                Button(actionTitle) { action?() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(action == nil ? PrivionyxTheme.Colors.tertiaryInk : PrivionyxTheme.Colors.accent)
                    .buttonStyle(.plain)
                    .disabled(action == nil)
            }
        }
    }
}

/// Uppercase eyebrow label ("THIS MONTH", "ACCOUNT").
struct GlassEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .kerning(0.4)
            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
    }
}

/// Rows stacked inside one glass panel, separated by hairlines.
struct GlassRowGroup<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .privionyxGlass(cornerRadius: cornerRadius)
    }
}

/// Hairline divider between rows in a `GlassRowGroup`.
struct GlassRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(PrivionyxTheme.Colors.separator)
            .frame(height: 1)
    }
}

// MARK: - Content components

/// Rounded tile showing a merchant's leading initial.
struct InitialTile: View {
    let text: String
    var tint: Color
    var size: CGFloat = 38
    /// Category tints are all saturated, so white reads on every one of them. Pass a
    /// darker value when tinting with a pale surface colour.
    var foreground: Color = .white

    private var initial: String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "?").uppercased()
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Labelled progress bar: name on the left, share on the right, filled track below.
struct CategoryShareBar: View {
    let name: String
    /// Share of total spending, 0...1.
    let share: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(Int((share * 100).rounded()))%")
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(PrivionyxTheme.Colors.track)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, share)) * proxy.size.width)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(Int((share * 100).rounded())) percent of spending")
    }
}

/// Smoothed line chart used in the summary card.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = PrivionyxTheme.Colors.accent

    var body: some View {
        GeometryReader { proxy in
            SparklinePath(values: values)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct SparklinePath: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let lowest = values.min() ?? 0
        let highest = values.max() ?? 0
        let span = highest - lowest
        let inset: CGFloat = 3

        let points = values.enumerated().map { index, value -> CGPoint in
            let x = rect.width * CGFloat(index) / CGFloat(values.count - 1)
            // A flat series draws through the middle rather than collapsing to the baseline.
            let normalized = span > 0 ? (value - lowest) / span : 0.5
            let y = rect.height - inset - CGFloat(normalized) * (rect.height - inset * 2)
            return CGPoint(x: x, y: y)
        }

        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

/// Percentage-change badge with a direction arrow.
struct TrendChip: View {
    /// Percentage change; negative values read as a decrease.
    let percentage: Int

    private var isIncrease: Bool { percentage >= 0 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isIncrease ? "arrow.up" : "arrow.down")
                .font(.system(size: 9, weight: .black))
            Text("\(abs(percentage))%")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(PrivionyxTheme.Colors.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(PrivionyxTheme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("\(isIncrease ? "Up" : "Down") \(abs(percentage)) percent versus last period")
    }
}

/// Small pill tag used for categories in sheets and rows.
struct CategoryTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(PrivionyxTheme.Colors.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(PrivionyxTheme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Square icon tile used by quick actions and settings rows.
struct GlassIconTile: View {
    let systemImage: String
    var tint: Color = PrivionyxTheme.Colors.accent
    var size: CGFloat = 34
    var isAccented: Bool = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(isAccented ? tint : PrivionyxTheme.Colors.ink.opacity(0.85))
            .frame(width: size, height: size)
            .background(
                isAccented ? PrivionyxTheme.Colors.accentSoft : PrivionyxTheme.Colors.glassFillStrong,
                in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            )
    }
}

/// Title/value line used in summaries and detail lists.
struct GlassValueRow: View {
    let title: String
    let value: String
    var isEmphasized: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: isEmphasized ? 14 : 13, weight: isEmphasized ? .bold : .semibold))
                .foregroundStyle(isEmphasized ? PrivionyxTheme.Colors.ink.opacity(0.7) : PrivionyxTheme.Colors.secondaryInk)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: isEmphasized ? 20 : 15, weight: isEmphasized ? .heavy : .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }
}

/// Tinted status pill.
struct GlassBadge: View {
    let title: String
    var tint: Color = PrivionyxTheme.Colors.accent
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Selectable pill used for category and filter rows.
struct GlassChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(isSelected ? PrivionyxTheme.Colors.onAccent : PrivionyxTheme.Colors.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(PrivionyxTheme.Colors.accent)
                }
            }
            .privionyxGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Circular glass control for header actions (back, edit, share).
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 40
    var accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(PrivionyxTheme.Colors.ink.opacity(0.75))
                .frame(width: size, height: size)
                .privionyxGlass(cornerRadius: size / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }
}

/// Guidance shown when a screen has nothing to display yet.
struct GlassEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassIconTile(systemImage: systemImage, size: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .privionyxGlass(cornerRadius: 16)
    }
}

/// Confirmation toast that floats above the tab bar.
struct GlassToast: View {
    let text: String
    var systemImage: String = "checkmark"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
            Text(text)
                .font(.system(size: 13.5, weight: .bold))
        }
        .foregroundStyle(PrivionyxTheme.Colors.onAccent)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(PrivionyxTheme.Colors.accent, in: Capsule())
        .shadow(color: PrivionyxTheme.Colors.accent.opacity(0.35), radius: 16, y: 6)
    }
}

/// Filled accent button matching the prototype's primary call to action.
struct GlassPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .heavy))
                .foregroundStyle(PrivionyxTheme.Colors.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(PrivionyxTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Translucent counterpart to `GlassPrimaryButton`.
struct GlassSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .privionyxGlass(cornerRadius: 14, strong: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Form fields

/// Labelled text entry in the glass style.
struct GlassTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isRequired: Bool = false
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                if isRequired {
                    Text("Required")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)
                }
            }

            Group {
                if let lineLimit {
                    TextField(prompt, text: $text, axis: axis)
                        .lineLimit(lineLimit)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .keyboardType(keyboardType)
            .foregroundStyle(PrivionyxTheme.Colors.fieldText)
            .padding(13)
            .privionyxGlass(cornerRadius: 14, strong: true)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        PrivionyxTheme.appBackground.ignoresSafeArea()

        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                InitialTile(text: "Blue Bottle", tint: PrivionyxTheme.Colors.accent)
                InitialTile(text: "Uber", tint: PrivionyxTheme.Colors.neutralTile, foreground: PrivionyxTheme.Colors.ink)
                TrendChip(percentage: 12)
                TrendChip(percentage: -4)
                CategoryTag(title: "Groceries")
            }

            CategoryShareBar(name: "Food & Dining", share: 0.32, tint: PrivionyxTheme.Colors.accent)
            Sparkline(values: [3, 8, 4, 14, 9, 18, 12, 22]).frame(height: 44)
            GlassToast(text: "Receipt saved")

            HStack(spacing: 10) {
                GlassSecondaryButton(title: "Retake") {}
                GlassPrimaryButton(title: "Save Receipt") {}
            }
        }
        .padding(20)
    }
}
