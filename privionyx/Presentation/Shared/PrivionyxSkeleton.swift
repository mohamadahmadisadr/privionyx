import SwiftUI

/// Placeholders shown in the shape of the content that is still being read.
///
/// The alternative — a spinner over the whole screen — makes the app unusable for as long as
/// the slowest thing takes, and tells the user nothing about what is coming. These keep the
/// page at its real size and in its real arrangement, so nothing jumps when the figures land.

/// Says in words what the placeholders say in shape.
///
/// Grey blocks on their own read as "something goes here"; they do not say that anything is
/// happening. This is the line that tells the user the app is working rather than empty.
struct SkeletonNotice: View {
    var title: String

    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// One grey stand-in: a line of text, a number, a tile.
///
/// Sized by the caller to match whatever it replaces. A `nil` width fills the space available,
/// which is what a full-width line of text does anyway.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    /// Off for Reduce Motion. A shape breathing at 0.9s is exactly the kind of unrequested
    /// looping movement the setting exists to stop; the placeholder still reads as one
    /// standing still.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PrivionyxTheme.Colors.track)
            .frame(width: width, height: height)
            .opacity(isDim ? 0.45 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isDim
            )
            .onAppear { isDim = true }
            .accessibilityHidden(true)
    }
}

/// Receipt rows in the shape the real ones take: initial tile, merchant, subtitle, amount.
///
/// Shared by the Dashboard's recent list and the Receipts screen, because both draw the same
/// row and a placeholder that doesn't match its content is just a different kind of jump.
struct SkeletonReceiptRows: View {
    var count: Int = 4

    var body: some View {
        GlassRowGroup {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 12) {
                    SkeletonBlock(width: 38, height: 38, cornerRadius: 10)

                    VStack(alignment: .leading, spacing: 6) {
                        // Varied so the block reads as a list of different merchants rather
                        // than as a rendering glitch.
                        SkeletonBlock(width: index.isMultiple(of: 2) ? 118 : 92, height: 11)
                        SkeletonBlock(width: index.isMultiple(of: 2) ? 74 : 96, height: 9)
                    }

                    Spacer(minLength: 8)

                    SkeletonBlock(width: 58, height: 12)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                if index < count - 1 {
                    GlassRowDivider()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading receipts")
    }
}
