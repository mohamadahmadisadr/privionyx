import SwiftUI

/// An ad, sitting in the flow of a screen's content between two of its sections.
///
/// Inline rather than pinned to the bottom edge: a floating bar covers whatever is beneath
/// it and follows the user everywhere, where a card in the scroll passes by once and can be
/// scrolled away from. It is styled as one of the app's own cards so it reads as part of the
/// page rather than as something stuck on top of it.
///
/// When there is no ad — not configured, not filled, or bought out of — this occupies
/// exactly zero points and the screen looks as it did before ads existed.
struct BannerAdSlot: View {
    let placement: AdPlacement

    @Environment(PrivionyxAppState.self) private var appState
    /// The height the ad reported. `nil` until it has reported anything, which is when the
    /// slot shows the space the provider asked to reserve.
    @State private var loadedHeight: CGFloat?
    @State private var isRemoveAdsPresented = false

    /// Reserved before the first ad arrives, collapsed to nothing if none ever does.
    private var height: CGFloat {
        loadedHeight ?? appState.bannerAds.preferredHeight()
    }

    var body: some View {
        if AdGate.showsBanner(
            entitlement: appState.purchases.entitlement,
            isConfigured: appState.bannerAds.isConfigured,
            isLaunching: appState.isLaunching
        ), height > 0 {
            VStack(spacing: 0) {
                appState.bannerAds.banner(placement: placement) { measured in
                    // Animated so a collapse on no-fill closes the gap rather than leaving
                    // the page mid-jump.
                    withAnimation(.easeOut(duration: 0.25)) { loadedHeight = measured }
                }
                .frame(height: height)
                .frame(maxWidth: .infinity)

                // A hairline and its padding between the creative and this app's own
                // control. Google treats a tappable element flush against an ad as an
                // accidental-click risk, and accidental clicks are what get an account
                // closed for invalid traffic.
                Rectangle()
                    .fill(PrivionyxTheme.Colors.separator)
                    .frame(height: 1)

                removeAdsLink
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PrivionyxTheme.Colors.glassStroke, lineWidth: 1)
            )
        }
    }

    /// The upsell, placed where the annoyance is rather than buried in Settings — but as a
    /// line of text, not a modal. It costs the user nothing to ignore.
    private var removeAdsLink: some View {
        Button {
            isRemoveAdsPresented = true
        } label: {
            Text("Remove ads")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(PrivionyxTheme.Colors.glassFillStrong)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isRemoveAdsPresented) {
            RemoveAdsSheet()
        }
    }
}
