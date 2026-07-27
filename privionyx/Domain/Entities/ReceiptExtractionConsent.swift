import Foundation

/// Whether a language model may read the user's receipts at all.
///
/// Only two answers, because only one question is worth interrupting for. A model already
/// installed on the device costs the user nothing to use — no download, no network, no data
/// leaving the phone — so asking permission per receipt would be a prompt with no decision
/// behind it. Fetching 2.6 GB is a different matter, and that is the one thing still asked.
enum ReceiptExtractionConsent: String, CaseIterable, Identifiable, Sendable {
    /// Use whichever model the device can run. The default.
    case useModelWhenAvailable
    /// Never use a model; the built-in parser reads everything.
    case alwaysUseBuiltIn

    static let storageKey = "privionyx.extractionConsent"
    /// Separate from the consent itself: turning down a 2.6 GB download is not the same
    /// statement as turning models off, and the two are undone independently.
    static let downloadPromptSuppressedKey = "privionyx.suppressGemmaExtractionDownloadPrompt"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .useModelWhenAvailable: "Use on-device AI"
        case .alwaysUseBuiltIn: "Always use built-in"
        }
    }

    var detail: String {
        switch self {
        case .useModelWhenAvailable:
            "Read receipts with Apple Intelligence or Gemma when your device has them. Slower, usually more accurate. Nothing leaves your iPhone."
        case .alwaysUseBuiltIn:
            "Read every receipt with the instant built-in parser. Never uses a model."
        }
    }
}

/// What should happen before a receipt is read.
enum ReceiptExtractionDecision: Equatable {
    /// Run the model that `resolve()` picked.
    case useModel
    /// Run the deterministic parser and nothing else.
    case useBuiltIn
    /// No model is installed, but Gemma could be downloaded to become one.
    case askToDownloadGemma
}

/// Turns "what can this device run" plus "what has the user already said" into one decision.
///
/// Pure and separate from the view model so the branch that matters — the only case where
/// the user is interrupted — can be tested without a camera, a model, or a screen.
enum ReceiptExtractionConsentPolicy {
    static func decide(
        modelIsReady: Bool,
        gemmaIsDownloadable: Bool,
        consent: ReceiptExtractionConsent,
        downloadPromptSuppressed: Bool
    ) -> ReceiptExtractionDecision {
        // An outright "no" ends it: no model, and no asking about downloading one either.
        // Someone who has turned models off is not waiting to be sold 2.6 GB of one.
        guard consent != .alwaysUseBuiltIn else { return .useBuiltIn }

        // Installed and usable — just use it. This is the case the app must never ask about.
        if modelIsReady { return .useModel }

        if gemmaIsDownloadable, downloadPromptSuppressed == false {
            return .askToDownloadGemma
        }

        return .useBuiltIn
    }
}
