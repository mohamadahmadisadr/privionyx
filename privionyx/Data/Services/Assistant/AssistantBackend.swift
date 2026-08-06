import Foundation

/// The assistant engines a user can pick between in Settings.
///
/// To add another engine (a cloud model, a bundled Core ML model, a mock for tests):
/// conform it to `ReceiptAssistant`, add a case here, and extend `title`, `detail`,
/// and `makeAssistant()`. No view or view model needs to change.
enum AssistantBackend: String, CaseIterable, Identifiable, Sendable {
    /// Deterministic offline analysis. Always available.
    case rules
    /// Apple's on-device foundation model. Private, but device-gated.
    case appleIntelligence
    /// Google's Gemma 4, run locally via LiteRT-LM. Private, but must be downloaded first.
    case localGemma

    static let storageKey = "privionyx.assistantBackend"
    static let fallback: AssistantBackend = .rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules:
            "Built-in"
        case .appleIntelligence:
            "Apple Intelligence"
        case .localGemma:
            "Gemma (On-Device)"
        }
    }

    var detail: String {
        switch self {
        case .rules:
            "Instant, offline answers computed directly from your receipts. Works on every device."
        case .appleIntelligence:
            "Natural conversation using Apple's on-device model. Nothing leaves your iPhone. Requires Apple Intelligence."
        case .localGemma:
            "Google's Gemma 4 running fully offline on your device. Downloads once, then nothing leaves your iPhone."
        }
    }

    /// One line, short enough for the Assistant header, naming where the work happens.
    ///
    /// This exists because App Review rejected 1.0 (9) under 5.1.1(i)/5.1.2(i) having read
    /// the Assistant tab as shipping receipts to a cloud AI service. It never did — but the
    /// tab said "AI Assistant / Understands every receipt you scan" and nothing else, so the
    /// reading was fair. The claim now travels with the engine that backs it.
    var processingSummary: String {
        switch self {
        case .rules:
            "On-device · no AI service involved"
        case .appleIntelligence:
            "On-device with Apple Intelligence · nothing is sent"
        case .localGemma:
            "On-device with Gemma · nothing is sent"
        }
    }

    /// Who does the processing, for the disclosure sheet. Named specifically: "on-device"
    /// alone doesn't tell a user which piece of software is reading their receipts.
    var processorDescription: String {
        switch self {
        case .rules:
            "Privionyx itself, using ordinary arithmetic over the receipts already on your iPhone. No model of any kind is involved."
        case .appleIntelligence:
            "Apple Intelligence — Apple's foundation model, built into iOS and running on your iPhone's own hardware. Apple does not receive your receipts."
        case .localGemma:
            "Google's Gemma model, running on your iPhone via LiteRT-LM. The model file was downloaded once; answering your questions uses no network connection, and Google does not receive your receipts."
        }
    }

    var icon: String {
        switch self {
        case .rules:
            "function"
        case .appleIntelligence:
            // `apple.intelligence` ships with iOS 26. An SF Symbol that does not exist on the
            // running system draws nothing at all — the row would simply lose its icon on
            // iOS 18 with no warning at build time, since the name is only a string.
            if #available(iOS 26.0, *) { "apple.intelligence" } else { "sparkles" }
        case .localGemma:
            "cpu"
        }
    }

    func makeAssistant() -> any ReceiptAssistant {
        switch self {
        case .rules:
            RuleBasedReceiptAssistant()
        case .appleIntelligence:
            // The framework is iOS 26 and later. Below that the stand-in reports why, which
            // Settings shows beside the option exactly as it shows "device not eligible".
            if #available(iOS 26.0, *) {
                FoundationModelsReceiptAssistant()
            } else {
                UnsupportedOSAssistant()
            }
        case .localGemma:
            LiteRTGemmaReceiptAssistant()
        }
    }
}
