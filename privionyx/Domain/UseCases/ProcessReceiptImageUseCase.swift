import UIKit

/// The stages of turning a photograph into a draft, in the order they run.
///
/// Reported so the capture overlay can say what is happening instead of animating a
/// fabricated percentage. Recognition dominates the wall clock; extraction is comparatively
/// instant.
enum ReceiptProcessingPhase: Equatable {
    case recognizing
    case extracting
    /// A language model is reading the receipt. Named separately because it is the one stage
    /// slow enough that the user deserves to know what is taking the time — and which engine
    /// is taking it.
    case consultingModel(ReceiptExtractionEngine)

    /// Shown under the spinner while this stage runs.
    var label: String {
        switch self {
        case .recognizing: "Reading the receipt…"
        case .extracting: "Extracting fields…"
        case let .consultingModel(engine): engine.processingLabel
        }
    }
}

struct ProcessReceiptImageUseCase {
    private let ocrService: any OCRService
    private let parser: any ReceiptParser
    private let resolveCategory: ResolveCategoryUseCase
    private let resolveMerchant: ResolveMerchantUseCase
    /// Resolved per run rather than injected as a fixed engine, because which model a device
    /// can run changes underneath the app — Apple Intelligence gets switched on, a Gemma
    /// download finishes, weights get deleted for disk space.
    private let engineResolver: ReceiptExtractionEngineResolver?

    init(
        ocrService: any OCRService,
        parser: any ReceiptParser,
        resolveCategory: ResolveCategoryUseCase,
        resolveMerchant: ResolveMerchantUseCase,
        engineResolver: ReceiptExtractionEngineResolver? = nil
    ) {
        self.ocrService = ocrService
        self.parser = parser
        self.resolveCategory = resolveCategory
        self.resolveMerchant = resolveMerchant
        self.engineResolver = engineResolver
    }

    /// - Parameter onPhase: Reports which stage is running as it starts. The two stages are
    ///   the only progress this pipeline can honestly report: Vision does not surface
    ///   incremental progress, and parsing is fast enough that subdividing it would be
    ///   invention. Callers that don't care can omit it.
    /// - Parameter allowsModel: Whether a language model may be consulted. The decision is
    ///   the caller's rather than this use case's, because it is the caller that has asked
    ///   the user and knows what they said — the pipeline only knows what the device could
    ///   run, which is a different question.
    func execute(
        image: UIImage,
        allowsModel: Bool = true,
        onPhase: @MainActor (ReceiptProcessingPhase) -> Void = { _ in }
    ) async throws -> ReceiptDraft {
        onPhase(.recognizing)
        let ocrResult = try await ocrService.recognizeText(in: image)

        onPhase(.extracting)
        let parsed = await parser.parse(ocrResult: ocrResult)

        guard allowsModel else { return makeDraft(from: parsed) }

        return makeDraft(from: await refined(parsed, rows: ocrResult.lines.map(\.text), onPhase: onPhase))
    }

    /// Hands the recognized rows to a language model when one is usable, and lets what it
    /// reads stand in for what the parser read.
    ///
    /// The model wins on every field it fills. That is a deliberate choice and not a free
    /// one: nothing checks its arithmetic, so a figure it invents reaches the draft the same
    /// way a figure it read does. What limits the damage is that the review screen is still
    /// between this and the saved receipt, and that a model returning nothing at all — the
    /// common failure — leaves the parser's answer untouched rather than blanking the form.
    private func refined(
        _ parsed: ParsedReceiptData,
        rows: [String],
        onPhase: @MainActor (ReceiptProcessingPhase) -> Void
    ) async -> ParsedReceiptData {
        guard let engineResolver else { return parsed }

        let resolution = await engineResolver.resolve()
        guard let extractor = resolution.extractor else { return parsed }

        onPhase(.consultingModel(resolution.engine))

        // A model that fails is not an error the user should see: the parser has already
        // produced a complete draft, and the honest outcome is to keep it.
        guard let extraction = try? await extractor.extract(
            from: rows,
            currencyCode: PrivionyxCurrencyFormatter.currentCurrencyCode
        ) else { return parsed }

        return extraction.applied(to: parsed)
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
