import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Field extraction through Apple's on-device model.
///
/// Preferred over Gemma wherever it runs, because it is already on the device: no download,
/// no 2.6 GB, no disk. It is also the more device-gated of the two — `availability()` is the
/// whole story about whether this is usable, and it is checked per call rather than cached,
/// since the user can switch Apple Intelligence off between one receipt and the next.
///
/// The whole runtime path is guarded by `#if canImport(FoundationModels)` so the app still
/// builds against an SDK without it, mirroring `FoundationModelsReceiptAssistant`.
@MainActor
final class FoundationModelsFieldExtractor: ReceiptFieldExtracting {
    nonisolated let engine: ReceiptExtractionEngine = .appleIntelligence

    private let dateExtractor = DateExtractor()

    func availability() async -> AssistantAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case let .unavailable(reason):
            return .unavailable(reason: description(for: reason))
        @unknown default:
            return .unavailable(reason: "Apple Intelligence is unavailable on this device.")
        }
        #else
        return .unavailable(reason: "This build was compiled without Apple Intelligence support.")
        #endif
    }

    func extract(from rows: [String], currencyCode: String) async throws -> ReceiptMLExtraction? {
        #if canImport(FoundationModels)
        guard rows.isEmpty == false else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        // A fresh session per receipt. There is no conversation to continue here, and a
        // session carried between receipts would put the last one's figures in the context
        // window of the next — the failure mode where a $41.29 total quietly reappears on
        // the receipt after it.
        let session = LanguageModelSession(instructions: ReceiptExtractionPrompt.instructions)
        let response = try await session.respond(
            to: ReceiptExtractionPrompt.prompt(rows: rows, currencyCode: currencyCode),
            generating: GeneratedReceiptFields.self
        )

        return response.content.extraction(dateParser: parseDate)
        #else
        return nil
        #endif
    }

    /// Reuses the parser's own date reader rather than a second one. A model told to answer
    /// in ISO does so most of the time; when it echoes the receipt's own format instead,
    /// this is already the code that knows how to read that.
    private func parseDate(_ text: String) -> Date? {
        dateExtractor.extractDate(from: [text])
    }

    #if canImport(FoundationModels)
    private func description(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to use this engine."
        case .modelNotReady:
            "Apple Intelligence is still preparing its model. Try again shortly."
        @unknown default:
            "Apple Intelligence is unavailable right now."
        }
    }
    #endif
}

#if canImport(FoundationModels)
/// The schema the model is constrained to fill.
///
/// Guided generation is the reason this engine needs no JSON reader: the model cannot
/// answer with prose, a fenced code block, or a field this app did not ask for, because the
/// framework builds its output against this type. Every field is optional so that "I could
/// not read it" stays expressible — a required `total` would force a number to be invented.
@Generable(description: "The fields printed on a shop receipt.")
struct GeneratedReceiptFields {
    @Guide(description: "The shop's name from the letterhead. Omit if not legible.")
    var merchant: String?

    @Guide(description: "The final amount paid for the goods, as a number. Not the cash tendered, not the change, not a discount.")
    var total: Double?

    @Guide(description: "The amount before tax, as a number. Omit when tax is included in the price.")
    var subtotal: Double?

    @Guide(description: "The tax charged, as a number.")
    var tax: Double?

    @Guide(description: "The tip or gratuity, as a number. Omit if the receipt has none.")
    var tip: Double?

    @Guide(description: "The transaction date in yyyy-MM-dd form.")
    var date: String?

    func extraction(dateParser: (String) -> Date?) -> ReceiptMLExtraction? {
        let trimmedMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraction = ReceiptMLExtraction(
            merchant: trimmedMerchant?.isEmpty == true ? nil : trimmedMerchant,
            amount: total,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            date: date.flatMap(dateParser)
        )
        return extraction.hasUsefulValues ? extraction : nil
    }
}
#endif
