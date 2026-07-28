import Foundation

/// Whether an ad may be requested at all, and whether the user has been asked.
///
/// Separate from `BannerAdProviding` because it answers a different question at a different
/// time: the banner provider is asked "what goes in this slot", once per screen, where this is
/// asked once per launch and before anything may be drawn at all. Behind a protocol for the
/// same reason as the rest of the ad stack — the app has to build, run, and be tested on a
/// machine where the SDK isn't present.
///
/// This exists because `npa=1` is not a substitute for consent. Asking for non-personalized
/// ads limits what an advertiser learns; it does not change that the SDK reads and writes
/// device storage, which is what the EEA and UK rules govern. Google enforces it from their
/// side: since January 2024 they decline to serve that traffic from an app with no certified
/// consent platform, and it arrives as an empty slot rather than as an error anyone would
/// notice.
@MainActor
protocol AdConsentProviding: AnyObject {
    /// Whether an ad request is allowed right now.
    ///
    /// False until the state has been resolved, and false afterwards for a user in a regulated
    /// region who declined. Outside those regions the SDK reports no consent requirement and
    /// this becomes true as soon as the first check completes.
    var canRequestAds: Bool { get }

    /// Whether the user has to be given a standing way to change their answer.
    ///
    /// True only for users who were shown a form: consent that cannot be withdrawn is not
    /// consent, and Google requires the entry point to be permanently reachable. Everyone
    /// else must not see it, which is why this is a separate question from `canRequestAds`.
    var isPrivacyOptionsRequired: Bool { get }

    /// Resolves the consent state, presenting a form if one is required. Once per launch.
    func requestConsentUpdate() async

    /// Reopens the form so a decision can be changed. Only ever from a tap.
    func presentPrivacyOptions() async
}

/// The consent provider for a build with no ad SDK in it.
///
/// Answers yes, because there is nothing here to gate: with no SDK linked `NoBannerAds`
/// already refuses to draw anything, and a second `false` would only make it ambiguous which
/// of the two is the reason the app shows no ads.
@MainActor
final class NoAdConsent: AdConsentProviding {
    var canRequestAds: Bool { true }

    var isPrivacyOptionsRequired: Bool { false }

    func requestConsentUpdate() async {}

    func presentPrivacyOptions() async {}
}
