import Foundation

nonisolated struct ReceiptParsingService {
    private let mlExtractor: (any ReceiptMLExtractor)?
    private let sanitizer: ReceiptTextSanitizer
    private let amountExtractor: AmountExtractor
    private let dateExtractor = DateExtractor()
    private let merchantExtractor = MerchantExtractor()
    private let categoryClassifier = CategoryClassifier()
    private let reconciler = ReceiptTotalsReconciler()
    private let lineItemExtractor = LineItemExtractor()

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
        // The model is consulted only where deterministic extraction found nothing. It used
        // to win outright wherever it produced a value, which meant an untrained model would
        // have outranked the extraction path the corpus actually exercises. No model ships in
        // the bundle today, so this is a guard against the day one does: if a model is ever
        // trained well enough to overrule the parser, the way to let it is to reconcile both
        // sets of figures and prefer whichever balances — not to trust it by default.
        let mlExtraction = positionedLines.isEmpty ? nil : mlExtractor?.extract(from: positionedLines)
        let merchant = merchantExtractor.extractMerchant(from: structuredLines)
            ?? mlExtraction?.merchant
            ?? "Unknown Merchant"
        let tax = amountExtractor.extractTax(from: structuredLines, positionedLines: positionedLines)
        let tip = amountExtractor.extractValue(from: structuredLines, positionedLines: positionedLines, matching: ["tip", "gratuity", "service", "service tip"])
        let explicitSubtotal = amountExtractor.extractExplicitSubtotal(from: structuredLines, positionedLines: positionedLines)
        // Items are only recoverable from positioned rows; the plain-text path has no
        // geometry to tell an item's price from any other number on the line.
        let lineItems = positionedLines.isEmpty
            ? []
            : lineItemExtractor.extractLineItems(from: positionedLines)
        let amountCandidates = amountExtractor.extractAmountCandidates(from: structuredLines, positionedLines: positionedLines)
        let amount = amountExtractor.selectBestAmount(
            from: amountCandidates,
            explicitSubtotal: explicitSubtotal,
            tax: tax,
            tip: tip,
            lineItems: lineItems
        ) ?? mlExtraction?.amount

        // The totals block is the only part of a receipt that can be checked against
        // itself, so every figure goes through reconciliation before it reaches the draft.
        let reconciled = reconciler.reconcile(
            total: amount,
            subtotal: explicitSubtotal ?? mlExtraction?.subtotal,
            tax: tax ?? mlExtraction?.tax,
            tip: tip ?? mlExtraction?.tip
        )
        // Sign is applied after reconciliation, not before it. Every guard in the reconciler
        // — "a subtotal above the total cannot be right", "tax beyond a fifth of the subtotal
        // is a misread" — is written about magnitudes, and a return's figures balance exactly
        // as a purchase's do. So the block is checked as printed and then flipped whole.
        let sign: Double = amountExtractor.isRefund(from: structuredLines, positionedLines: positionedLines) ? -1 : 1
        let resolvedAmount = reconciled.total.map { $0 * sign } ?? .zero
        let subtotal = reconciled.subtotal.map { $0 * sign }
        let resolvedTax = reconciled.tax.map { $0 * sign }
        let resolvedTip = reconciled.tip.map { $0 * sign }
        let date = dateExtractor.extractDate(from: structuredLines) ?? mlExtraction?.date ?? .now
        let category = categoryClassifier.categorize(merchant: merchant, lines: structuredLines)
        let notes = ""

        return ParsedReceiptData(
            merchant: merchant,
            amount: resolvedAmount,
            subtotal: subtotal,
            tax: resolvedTax,
            tip: resolvedTip,
            date: date,
            category: category,
            rawText: rawText,
            lineItems: lineItems,
            notes: notes,
            derivedTotals: reconciled.derived,
            totalsStatus: reconciled.status
        )
    }
}

extension ReceiptParsingService: ReceiptParser {}
