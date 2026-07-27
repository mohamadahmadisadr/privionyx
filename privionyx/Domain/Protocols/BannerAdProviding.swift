import SwiftUI

/// Where in the app a banner sits.
///
/// Each place gets its own ad, kept alive for as long as the app runs. Screens that build
/// their content lazily destroy and rebuild whatever scrolls out of view, and without an
/// identity to cache against, every scroll past a banner would fire a fresh ad request —
/// billing advertisers for impressions nobody saw, which is how an AdMob account gets
/// closed for invalid traffic.
enum AdPlacement: String, CaseIterable, Sendable {
    case dashboard
    case receipts
    case assistant
    case settings
}

/// Supplies the banner, if there is one to supply.
///
/// The ad SDK is reached only through this, for the same reason the assistant engines are
/// reached through `ReceiptAssistant`: the app has to build, run, and be tested on a machine
/// where the SDK isn't present, and no screen should know which network is serving.
@MainActor
protocol BannerAdProviding: AnyObject {
    /// Whether an ad network is configured at all. False on a build with no SDK linked and
    /// no unit id, which is the state the app ships in until both are supplied.
    var isConfigured: Bool { get }

    /// The height to give the slot before anything has loaded.
    ///
    /// Reserved rather than grown into, because the ad SDK refuses to load into a
    /// zero-height view — it reports "Invalid ad width or height" and never calls back, so a
    /// slot that waits for an ad before making room waits forever. The height is a pure
    /// function of the screen, known before any request is made.
    func preferredHeight() -> CGFloat

    /// The banner for `placement`, reporting the height it ends up occupying.
    ///
    /// `0` means no fill: the slot collapses and the app looks like it has no ads, rather
    /// than leaving a grey rectangle where one would have been.
    func banner(placement: AdPlacement, onHeightChange: @escaping (CGFloat) -> Void) -> AnyView
}

/// The provider used when no ad SDK is linked. Renders nothing and reports nothing.
@MainActor
final class NoBannerAds: BannerAdProviding {
    var isConfigured: Bool { false }

    func preferredHeight() -> CGFloat { 0 }

    func banner(placement: AdPlacement, onHeightChange: @escaping (CGFloat) -> Void) -> AnyView {
        onHeightChange(0)
        return AnyView(EmptyView())
    }
}

/// Whether a banner may be shown at this moment.
///
/// Separated from the view so the rules are stated once and can be tested without a
/// rendering pass. Every one of them exists to answer a way an ad could be obnoxious or
/// get the app rejected.
enum AdGate {
    static func showsBanner(entitlement: AdEntitlement, isConfigured: Bool, isLaunching: Bool) -> Bool {
        // Paid for silence.
        guard entitlement.removesAds == false else { return false }
        // Nothing to show.
        guard isConfigured else { return false }
        // Not over the launch screen: an ad before the app has drawn its own content reads as
        // an interstitial, which is not what was agreed to and not what this is.
        guard isLaunching == false else { return false }
        return true
    }
}
