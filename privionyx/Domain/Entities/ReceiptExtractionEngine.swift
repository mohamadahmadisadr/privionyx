import Foundation

/// The engines that can read fields off a receipt, in the order they are preferred.
///
/// Preference is by capability, not by taste: a language model reads a layout it has never
/// seen far better than a rule can, so whichever one the device can actually run is used,
/// and the deterministic parser is what everything falls back to. That fallback is not a
/// lesser mode — it is the only engine guaranteed to exist on every device, and it is what
/// the corpus measures.
enum ReceiptExtractionEngine: String, CaseIterable, Identifiable, Sendable {
    /// Apple's on-device model. Nothing to download, but the device must support
    /// Apple Intelligence and have it switched on.
    case appleIntelligence
    /// Gemma 4 through LiteRT-LM. Runs on more devices than Apple Intelligence, but only
    /// after the user has downloaded ~2.6 GB of weights.
    case localGemma
    /// The deterministic parser. Always available, always the floor.
    case rules

    var id: String { rawValue }

    /// Tried in this order; the first available one wins.
    static let preferenceOrder: [ReceiptExtractionEngine] = [.appleIntelligence, .localGemma, .rules]

    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .localGemma: "Gemma (On-Device)"
        case .rules: "Built-in"
        }
    }

    /// Shown under the spinner while this engine reads the receipt. The built-in parser is
    /// fast enough that naming it would be a flicker, so it keeps the neutral wording.
    var processingLabel: String {
        switch self {
        case .appleIntelligence: "Reading with Apple Intelligence…"
        case .localGemma: "Reading with Gemma…"
        case .rules: "Extracting fields…"
        }
    }

    /// Whether this engine is a language model rather than the rule set. Used to decide
    /// whether a result is worth overriding the parser with.
    var isLanguageModel: Bool { self != .rules }
}
