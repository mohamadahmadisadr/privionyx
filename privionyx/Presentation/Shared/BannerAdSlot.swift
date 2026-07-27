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
                .padding(.vertical, 5)
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

/// The purchase itself, reachable from the banner and from Settings.
struct RemoveAdsSheet: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 68, height: 68)
                    .background(PrivionyxTheme.Colors.accentSoft, in: Circle())
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text("Remove Ads")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text("A one-time purchase. Ads disappear everywhere in the app, on every device signed in to your Apple ID.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let failure = appState.purchases.lastFailure {
                    Text(failure)
                        .font(.system(size: 12))
                        .foregroundStyle(PrivionyxTheme.Colors.warning)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                GlassPrimaryButton(title: purchaseTitle) {
                    Task {
                        if await appState.purchases.purchaseAdFree() { dismiss() }
                    }
                }
                .disabled(appState.purchases.isBusy || appState.purchases.displayPrice == nil)
                .opacity(appState.purchases.isBusy || appState.purchases.displayPrice == nil ? 0.5 : 1)

                GlassSecondaryButton(title: "Restore Purchases") {
                    Task {
                        if await appState.purchases.restorePurchases() { dismiss() }
                    }
                }
                .disabled(appState.purchases.isBusy)
            }
            .padding(22)
        }
        .presentationDetents([.height(380)])
        .task { await appState.purchases.refresh() }
    }

    /// Shows the real storefront price once known — "$4.99", "£4.49", "¥800" — rather than a
    /// hardcoded figure that would be wrong everywhere outside the United States.
    private var purchaseTitle: String {
        guard let price = appState.purchases.displayPrice else { return "Loading…" }
        return "Remove Ads · \(price)"
    }
}
