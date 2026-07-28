#if canImport(UserMessagingPlatform)
import UserMessagingPlatform

/// Google's User Messaging Platform, behind `AdConsentProviding`.
///
/// UMP is a Google-certified consent platform, which is the specific thing their EU user
/// consent policy requires — a hand-rolled "Allow ads?" alert satisfies neither the policy nor
/// the IAB signal the SDK actually reads. It arrives as a dependency of the Mobile Ads package
/// rather than as a separate one to add, so this needs no project change.
///
/// The form's contents are not defined here. They are configured once in the AdMob console
/// under Privacy & messaging, and the SDK downloads whatever is published there; an app that
/// never had a message configured gets `FormStatus.unavailable` and no form, which looks
/// identical to a user who does not need one. That is the most likely reason for this to be
/// silently doing nothing.
@MainActor
@Observable
final class GoogleAdConsentProvider: AdConsentProviding {
    /// False until the first check answers. Deliberately the pessimistic start: a slot that
    /// stays empty for one extra second costs an impression, where a request sent before the
    /// user has been asked is the thing that gets an app pulled from serving.
    private(set) var canRequestAds = false
    private(set) var isPrivacyOptionsRequired = false

    /// Forces the consent flow on for a debug build, so the form can be seen without a device
    /// in Europe. Simulators are always debug devices to UMP; a physical one has to name its
    /// hashed id, which the SDK prints to the console on the first run without it.
    static let forceEEALaunchArgument = "-privionyxAdConsentEEA"

    func requestConsentUpdate() async {
        // The error is deliberately ignored rather than surfaced. A failed update — usually
        // no network on a cold launch — leaves `consentStatus` holding the previous session's
        // answer, which is the right answer to act on and better than treating a dropped
        // request as a refusal. There is nothing here the user could act on either.
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: Self.parameters()) { _ in
                continuation.resume()
            }
        }
        readState()

        // Presents only when the SDK says a form is required, and returns on the next run loop
        // when it isn't — so this costs a user outside a regulated region nothing.
        //
        // `from: nil` lets UMP find the top view controller itself. The alternative is
        // threading one down from the scene, which would put UIKit in the launch path for a
        // presentation that happens for a minority of users and at most once each.
        await withCheckedContinuation { continuation in
            ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                continuation.resume()
            }
        }
        readState()
    }

    func presentPrivacyOptions() async {
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: nil) { _ in
                continuation.resume()
            }
        }
        // The user may have just withdrawn consent, which has to stop the next ad request.
        readState()
    }

    /// Copies what the SDK now believes into the two answers the app acts on.
    ///
    /// Read back from `ConsentInformation` rather than inferred from what the form returned:
    /// the SDK reconciles a stored IAB TCF string written by a previous session, and the
    /// completion handler says only that the form is gone, not what is now allowed.
    private func readState() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private static func parameters() -> RequestParameters {
        let parameters = RequestParameters()
        // The app is not directed at children and collects nothing that would change if it
        // were. Stated rather than left at its default so the claim is in the source.
        parameters.isTaggedForUnderAgeOfConsent = false

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(forceEEALaunchArgument) {
            let debug = DebugSettings()
            debug.geography = .EEA
            parameters.debugSettings = debug
        }
        #endif

        return parameters
    }
}
#endif
