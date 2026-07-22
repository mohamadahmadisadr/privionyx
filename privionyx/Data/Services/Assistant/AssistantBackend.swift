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

    static let storageKey = "privionyx.assistantBackend"
    static let fallback: AssistantBackend = .rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules:
            "Built-in"
        case .appleIntelligence:
            "Apple Intelligence"
        }
    }

    var detail: String {
        switch self {
        case .rules:
            "Instant, offline answers computed directly from your receipts. Works on every device."
        case .appleIntelligence:
            "Natural conversation using Apple's on-device model. Nothing leaves your iPhone. Requires Apple Intelligence."
        }
    }

    var icon: String {
        switch self {
        case .rules:
            "function"
        case .appleIntelligence:
            "apple.intelligence"
        }
    }

    func makeAssistant() -> any ReceiptAssistant {
        switch self {
        case .rules:
            RuleBasedReceiptAssistant()
        case .appleIntelligence:
            FoundationModelsReceiptAssistant()
        }
    }
}
