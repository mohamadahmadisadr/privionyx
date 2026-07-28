import Foundation

/// What to say, and what to run, when Apple Intelligence cannot exist on this system.
///
/// The FoundationModels framework is iOS 26 and later. The app deploys to iOS 18, so its two
/// wrappers — `FoundationModelsReceiptAssistant` and `FoundationModelsFieldExtractor` — are
/// marked `@available(iOS 26.0, *)` and simply do not exist on an older system.
///
/// Rather than thread an optional through every caller, each construction site picks between
/// the real thing and a stand-in from here. Both protocols already have a channel for "I
/// cannot run": `availability()`. An old system is just one more reason, alongside a device
/// that is not eligible and a user who has not turned the feature on — and it arrives at the
/// UI through the same path, so Settings explains it without knowing this file exists.
enum AppleIntelligenceSupport {
    /// Shown wherever the option appears on a system too old to have the framework.
    ///
    /// Phrased as the requirement rather than as a failure. A user on iOS 18 has not done
    /// anything wrong, and unlike an ineligible device this one is fixable by updating.
    static let unsupportedOSReason = "Apple Intelligence requires iOS 26 or later."
}

/// Stands in for `FoundationModelsReceiptAssistant` below iOS 26.
///
/// It answers nothing and says why. It is never selected silently: `availability()` reports
/// the reason, Settings shows it next to the option, and the app falls back to the built-in
/// engine — which needs no model at all and works on every system the app supports.
struct UnsupportedOSAssistant: ReceiptAssistant {
    func availability() async -> AssistantAvailability {
        .unavailable(reason: AppleIntelligenceSupport.unsupportedOSReason)
    }

    func suggestedPrompts(for context: AssistantContext) -> [String] {
        // The chips are computed from the user's own receipts and cost nothing to offer, so
        // they stay useful even though this engine cannot answer them. Whichever engine the
        // user falls back to can.
        ReceiptAssistantPromptBuilder.suggestedPrompts(for: context)
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        throw AssistantError.unavailable(AppleIntelligenceSupport.unsupportedOSReason)
    }
}

/// Stands in for `FoundationModelsFieldExtractor` below iOS 26.
///
/// `ReceiptExtractionEngineResolver` asks each extractor whether it is available and moves on
/// to the next when it is not, so reporting unavailable here is the whole of the behaviour:
/// extraction falls through to Gemma if it is downloaded, and to the rule-based parser
/// otherwise. Scanning a receipt keeps working on iOS 18; it just uses the parser.
struct UnsupportedOSFieldExtractor: ReceiptFieldExtracting {
    nonisolated var engine: ReceiptExtractionEngine { .appleIntelligence }

    func availability() async -> AssistantAvailability {
        .unavailable(reason: AppleIntelligenceSupport.unsupportedOSReason)
    }

    func extract(from rows: [String], currencyCode: String) async throws -> ReceiptMLExtraction? {
        nil
    }
}
