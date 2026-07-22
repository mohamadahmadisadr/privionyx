import UIKit

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

    func execute(image: UIImage) async throws -> ReceiptDraft {
        let ocrResult = try await ocrService.recognizeText(in: image)
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
