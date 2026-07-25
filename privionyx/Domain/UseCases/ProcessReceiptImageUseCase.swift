import UIKit

/// The stages of turning a photograph into a draft, in the order they run.
///
/// Reported so the capture overlay can say what is happening instead of animating a
/// fabricated percentage. Recognition dominates the wall clock; extraction is comparatively
/// instant.
enum ReceiptProcessingPhase: Equatable {
    case recognizing
    case extracting

    /// Shown under the spinner while this stage runs.
    var label: String {
        switch self {
        case .recognizing: "Reading the receipt…"
        case .extracting: "Extracting fields…"
        }
    }
}

struct ProcessReceiptImageUseCase {
    private let ocrService: any OCRService
    private let parser: any ReceiptParser
    private let resolveCategory: ResolveCategoryUseCase
    private let resolveMerchant: ResolveMerchantUseCase

    init(
        ocrService: any OCRService,
        parser: any ReceiptParser,
        resolveCategory: ResolveCategoryUseCase,
        resolveMerchant: ResolveMerchantUseCase
    ) {
        self.ocrService = ocrService
        self.parser = parser
        self.resolveCategory = resolveCategory
        self.resolveMerchant = resolveMerchant
    }

    /// - Parameter onPhase: Reports which stage is running as it starts. The two stages are
    ///   the only progress this pipeline can honestly report: Vision does not surface
    ///   incremental progress, and parsing is fast enough that subdividing it would be
    ///   invention. Callers that don't care can omit it.
    func execute(
        image: UIImage,
        onPhase: @MainActor (ReceiptProcessingPhase) -> Void = { _ in }
    ) async throws -> ReceiptDraft {
        await onPhase(.recognizing)
        let ocrResult = try await ocrService.recognizeText(in: image)

        await onPhase(.extracting)
        let parsed = await parser.parse(ocrResult: ocrResult)

        return makeDraft(from: parsed)
    }

    func execute(rawText: String) async -> ReceiptDraft {
        let parsed = await parser.parse(rawText: rawText)
        return makeDraft(from: parsed)
    }

    private func makeDraft(from parsed: ParsedReceiptData) -> ReceiptDraft {
        // Applied before the category lookup so a corrected name also matches its rule.
        let merchant = resolveMerchant.execute(recognized: parsed.merchant)

        return ReceiptDraft(
            merchant: merchant,
            amount: parsed.amount,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            tip: parsed.tip,
            date: parsed.date,
            category: resolveCategory.execute(merchant: merchant, fallback: parsed.category),
            imageData: nil,
            rawText: parsed.rawText,
            lineItems: parsed.lineItems,
            notes: parsed.notes,
            status: .scanned,
            derivedTotals: parsed.derivedTotals,
            totalsStatus: parsed.totalsStatus
        )
    }
}
