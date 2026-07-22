import Foundation

struct ReceiptParsingService {
    private let mlExtractor: (any ReceiptMLExtractor)?
    private let sanitizer: ReceiptTextSanitizer
    private let amountExtractor: AmountExtractor
    private let dateExtractor = DateExtractor()
    private let merchantExtractor = MerchantExtractor()
    private let categoryClassifier = CategoryClassifier()

    init(mlExtractor: (any ReceiptMLExtractor)? = nil) {
        self.mlExtractor = mlExtractor
        let sanitizer = ReceiptTextSanitizer()
        self.sanitizer = sanitizer
        self.amountExtractor = AmountExtractor(sanitizer: sanitizer)
    }

    func parse(rawText: String) async -> ParsedReceiptData {
        let cleanedLines = rawText
            .components(separatedBy: .newlines)
            .map(sanitizer.cleanedReceiptLine)
            .filter { $0.isEmpty == false }

        return await parse(rawText: rawText, structuredLines: cleanedLines, positionedLines: [])
    }

    func parse(ocrResult: OCRResult) async -> ParsedReceiptData {
        let structuredLines = ocrResult.lines
            .map { sanitizer.cleanedReceiptLine($0.text) }
            .filter { $0.isEmpty == false }
        return await parse(rawText: ocrResult.rawText, structuredLines: structuredLines, positionedLines: ocrResult.lines)
    }

    private func parse(rawText: String, structuredLines: [String], positionedLines: [OCRTextLine]) async -> ParsedReceiptData {
        let mlExtraction = positionedLines.isEmpty ? nil : mlExtractor?.extract(from: positionedLines)
        let merchant = mlExtraction?.merchant ?? merchantExtractor.extractMerchant(from: structuredLines) ?? "Unknown Merchant"
        let tax = amountExtractor.extractTax(from: structuredLines, positionedLines: positionedLines)
        let tip = amountExtractor.extractValue(from: structuredLines, positionedLines: positionedLines, matching: ["tip", "gratuity", "service", "service tip"])
        let explicitSubtotal = amountExtractor.extractExplicitSubtotal(from: structuredLines, positionedLines: positionedLines)
        let lineItems: [ReceiptLineItem] = []
        let amountCandidates = amountExtractor.extractAmountCandidates(from: structuredLines, positionedLines: positionedLines)
        let amount = mlExtraction?.amount ?? amountExtractor.selectBestAmount(
            from: amountCandidates,
            explicitSubtotal: explicitSubtotal,
            tax: tax,
            tip: tip,
            lineItems: lineItems
        ) ?? .zero
        let subtotal = mlExtraction?.subtotal ?? explicitSubtotal ?? amountExtractor.deriveSubtotal(total: amount, tax: tax, tip: tip)
        let resolvedTax = mlExtraction?.tax ?? tax
        let resolvedTip = mlExtraction?.tip ?? tip
        let date = mlExtraction?.date ?? dateExtractor.extractDate(from: structuredLines) ?? .now
        let category = categoryClassifier.categorize(merchant: merchant, lines: structuredLines)
        let notes = ""

        return ParsedReceiptData(
            merchant: merchant,
            amount: amount,
            subtotal: subtotal,
            tax: resolvedTax,
            tip: resolvedTip,
            date: date,
            category: category,
            rawText: rawText,
            lineItems: lineItems,
            notes: notes
        )
    }
}

extension ReceiptParsingService: ReceiptParser {}
