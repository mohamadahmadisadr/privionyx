import Foundation

/// An engine that reads a receipt's fields out of recognized text.
///
/// The deterministic parser is one of these and is always present; the others are language
/// models that may or may not be usable on a given device. `AssistantBackend` is the same
/// idea for the chat assistant — this is its extraction-side twin, and the two deliberately
/// share `AssistantAvailability` so a device's story about what it can run is told once.
///
/// `@MainActor` because the on-device runtimes require it: `LiteRTGemmaReceiptAssistant`
/// documents that its C handle is kept safe by main-actor ordering rather than by locking,
/// and there is no reason for extraction to be the exception that breaks that.
@MainActor
protocol ReceiptFieldExtracting {
    /// Which engine this is, for the phase label and for Settings.
    nonisolated var engine: ReceiptExtractionEngine { get }

    /// Whether this engine can serve a request on this device right now.
    func availability() async -> AssistantAvailability

    /// Reads what it can from `rows`, which are the receipt's recognized lines in reading
    /// order. Returning `nil` — or any field left `nil` — means "I could not tell", which is
    /// different from a value of zero and is what lets the caller fall back per field.
    func extract(from rows: [String], currencyCode: String) async throws -> ReceiptMLExtraction?
}
