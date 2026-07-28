import SwiftUI

// MARK: - State

/// The two ways out of the paywall.
enum PaywallAction: Equatable {
    case purchase
    case restore
}

/// What the paywall is doing — which is not the same as what the store is doing.
///
/// Keeping the two apart is the whole point of this type. The store is busy from the moment
/// the sheet appears: fetching the product is a network round trip that can take seconds, or
/// time out, or come back empty because the Paid Applications Agreement is unsigned. The
/// sheet used to publish all of it — a primary button reading "Loading…", and a line of
/// warning text under the title — to someone who had opened the sheet a quarter of a second
/// earlier and had not yet asked for anything. That reads as a broken app before the user has
/// even learned what is for sale.
///
/// So store status is the app's problem right up until the user taps. What is on screen at
/// rest is the offer; what replaces it is the outcome of something they chose to do.
enum PaywallStage: Equatable {
    /// The offer, and nothing else. Where the sheet always opens.
    case offer
    /// The user tapped and StoreKit has the request.
    case working(PaywallAction)
    /// It went through. Which action got them here decides what the sheet says.
    case settled(PaywallAction)
    /// It didn't go through, with a reason worth reading.
    case failed(String)

    /// Whether the offer's own copy — name, details, buttons — is what's on screen.
    ///
    /// True while working and while failed: a failure annotates the offer rather than
    /// replacing it, because the next thing the user wants is the button they just missed.
    var showsOffer: Bool {
        switch self {
        case .offer, .working, .failed: true
        case .settled: false
        }
    }

    /// The reason the last attempt failed, if the last attempt failed.
    ///
    /// Never populated by anything the user didn't ask for — an unreachable App Store at
    /// sheet-open time is not a failure, because nothing was attempted.
    var failureMessage: String? {
        if case let .failed(message) = self { return message }
        return nil
    }

    /// Whether an attempt is in flight, so both buttons can refuse a second tap.
    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// Resolves a finished attempt.
    ///
    /// `failure` is `nil` for a user who cancelled the App Store's own sheet — a deliberate
    /// non-event, which returns to the offer saying nothing. Telling someone who just tapped
    /// Cancel that their purchase did not complete is nagging.
    static func outcome(of action: PaywallAction, succeeded: Bool, failure: String?) -> PaywallStage {
        if succeeded { return .settled(action) }
        if let failure { return .failed(failure) }
        return .offer
    }
}

/// Every string on the paywall that depends on state, in one place so it can be asserted
/// without a running app.
enum PaywallCopy {
    static let productName = "Remove Ads"
    static let tagline = "One payment. No ads, ever again."

    /// What the money buys, stated plainly. Three lines, because a fourth stops being read.
    static let details: [(icon: String, text: String)] = [
        ("nosign", "No banner ads anywhere in Privionyx"),
        ("infinity", "A one-time purchase, not a subscription"),
        ("icloud", "Works on every device signed in to your Apple ID"),
    ]

    /// The buy button.
    ///
    /// "Unlock Forever" is the constant part and it is on screen in the first frame; the
    /// price is appended when the storefront answers. The price is never invented here —
    /// Apple derives every country's from the one price point set in App Store Connect, so a
    /// hardcoded "$4.99" is wrong everywhere but one storefront.
    static func unlockTitle(price: String?, stage: PaywallStage) -> String {
        if stage == .working(.purchase) { return "Unlocking…" }
        guard let price, price.isEmpty == false else { return "Unlock Forever" }
        return "Unlock Forever · \(price)"
    }

    static func restoreTitle(stage: PaywallStage) -> String {
        if stage == .working(.restore) { return "Restoring…" }
        return "Restore Purchase"
    }

    /// The headline over a finished purchase or restore.
    static func settledTitle(_ action: PaywallAction) -> String {
        switch action {
        case .purchase: "Ads removed"
        case .restore: "Purchase restored"
        }
    }

    static func settledDetail(_ action: PaywallAction) -> String {
        switch action {
        case .purchase: "Thanks. Privionyx is ad-free from here on, on every device signed in to your Apple ID."
        case .restore: "Found it. Privionyx is ad-free again on this device."
        }
    }
}

// MARK: - Sheet

/// The purchase itself, reachable from the banner and from Settings.
struct RemoveAdsSheet: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var stage: PaywallStage = .offer

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            Group {
                if stage.showsOffer {
                    offer
                } else if case let .settled(action) = stage {
                    settled(action)
                }
            }
            .padding(22)
        }
        .presentationDetents([.height(stage.showsOffer ? 480 : 340)])
        .animation(.easeInOut(duration: 0.2), value: stage)
        .task {
            // A failure left over from an earlier visit — or from the Restore row in
            // Settings, which writes to the same store — is not this sheet's news to break.
            appState.purchases.clearFailure()
            stage = .offer
            // Fetches the price in the background. Nothing on screen waits for it: the button
            // gains a price when one arrives and is tappable either way.
            await appState.purchases.refresh()
        }
    }

    // MARK: Offer

    private var offer: some View {
        VStack(spacing: 16) {
            badge(systemName: "nosign", tint: PrivionyxTheme.Colors.accent)

            VStack(spacing: 5) {
                Text(PaywallCopy.productName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(PaywallCopy.tagline)
                    .font(.system(size: 13.5))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(PaywallCopy.details, id: \.text) { detail in
                    Label {
                        Text(detail.text)
                            .font(.system(size: 13))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: detail.icon)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                            .frame(width: 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if let message = stage.failureMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(PrivionyxTheme.Colors.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            GlassPrimaryButton(
                title: PaywallCopy.unlockTitle(price: appState.purchases.displayPrice, stage: stage)
            ) {
                attempt(.purchase) { await appState.purchases.purchaseAdFree() }
            }
            .disabled(stage.isWorking)
            .opacity(stage.isWorking ? 0.5 : 1)

            GlassSecondaryButton(title: PaywallCopy.restoreTitle(stage: stage)) {
                attempt(.restore) { await appState.purchases.restorePurchases() }
            }
            .disabled(stage.isWorking)
            .opacity(stage.isWorking ? 0.5 : 1)
        }
    }

    // MARK: Settled

    private func settled(_ action: PaywallAction) -> some View {
        VStack(spacing: 16) {
            badge(systemName: "checkmark.seal.fill", tint: PrivionyxTheme.Colors.success)

            VStack(spacing: 5) {
                Text(PaywallCopy.settledTitle(action))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(PaywallCopy.settledDetail(action))
                    .font(.system(size: 13.5))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            // Dismissed on a tap rather than a timer: the banners are already gone behind
            // this sheet, and a sheet that closes itself mid-sentence is its own annoyance.
            GlassPrimaryButton(title: "Done") { dismiss() }
        }
    }

    private func badge(systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 66, height: 66)
            .background(tint.opacity(0.14), in: Circle())
            .padding(.top, 6)
    }

    /// Runs one attempt and puts its result on screen.
    ///
    /// `lastFailure` is cleared first so the message read back afterwards can only be this
    /// attempt's. The store sets it for everything worth reporting and leaves it alone for a
    /// user-cancelled purchase, which is what makes a cancel silent here.
    private func attempt(_ action: PaywallAction, _ work: @escaping () async -> Bool) {
        guard stage.isWorking == false else { return }
        stage = .working(action)

        Task {
            appState.purchases.clearFailure()
            let succeeded = await work()
            stage = .outcome(of: action, succeeded: succeeded, failure: appState.purchases.lastFailure)
        }
    }
}
