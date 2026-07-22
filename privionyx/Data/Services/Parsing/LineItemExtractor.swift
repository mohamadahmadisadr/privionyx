import Foundation

/// Pulls the purchased items out of the body of a receipt.
///
/// This is only tractable once rows carry their own amounts: an item is a row whose text
/// ends in a price, sitting between the letterhead and the totals block. Before row
/// assembly the name and the price arrived as separate observations and there was no way
/// to say which price belonged to which line.
///
/// Items earn their keep twice over — they are worth showing, and their sum is a second,
/// independent check on the subtotal, arrived at without reusing any figure from the
/// totals block.
struct LineItemExtractor {
    private let sanitizer: ReceiptTextSanitizer

    init(sanitizer: ReceiptTextSanitizer = ReceiptTextSanitizer()) {
        self.sanitizer = sanitizer
    }

    private static let amountExtractor = AmountExtractor()

    /// Rows at or below the first of these end the item list. Tax rows count: a receipt
    /// that reaches its tax has finished listing purchases, and not every receipt labels
    /// the boundary "SUBTOTAL" — one in the corpus goes straight from items to "Food",
    /// "Service Charge", "Tax", "Payment Due", which left the fee and the total itself
    /// being counted as things that were bought.
    private static let totalsTokens = [
        "subtotal", "sub total", "sous-total", "sous total", "net sales",
        "total", "amount due", "balance due", "payment due", "amount payable",
        "item count", "items sold",
        "tax", "hst", "gst", "vat", "tps", "tvq", "qst", "pst",
        "service charge", "gratuity"
    ]

    /// Body rows that carry a price but are not purchases.
    private static let excludedTokens = [
        "change", "cash", "tend", "tender", "debit", "credit", "visa", "mastercard",
        "interac", "approval", "auth", "balance", "savings", "saved", "discount",
        "points", "reward", "loyalty", "ct money", "triangle", "account"
    ]

    func extractLineItems(from lines: [OCRTextLine]) -> [ReceiptLineItem] {
        guard lines.isEmpty == false else { return [] }

        let body = lines.prefix(while: { Self.isTotalsRow($0.text, sanitizer: sanitizer) == false })
        return body.compactMap { lineItem(from: $0.text) }
    }

    private static func isTotalsRow(_ text: String, sanitizer: ReceiptTextSanitizer) -> Bool {
        let normalized = sanitizer.normalizedTokenLine(text)
        return totalsTokens.contains { MerchantExtractor.containsWord($0, in: normalized) }
    }

    private func lineItem(from text: String) -> ReceiptLineItem? {
        guard Self.isUnitPriceRow(text) == false else { return nil }

        let amounts = Self.amountExtractor.extractAmounts(in: text)
        guard let amount = amounts.last, amount > 0 else { return nil }

        let normalized = sanitizer.normalizedTokenLine(text)
        guard Self.excludedTokens.contains(where: { MerchantExtractor.containsWord($0, in: normalized) }) == false
        else { return nil }

        guard let name = Self.itemName(from: text), name.isEmpty == false else { return nil }

        return ReceiptLineItem(name: name, quantity: Self.quantity(from: text), amount: amount)
    }

    /// A per-unit breakdown printed under its item — "4EA @ 2.59/EA", "2 @ 6.99". The
    /// figure is a rate, not a charge, and adding it double-counts against the line above.
    private static func isUnitPriceRow(_ text: String) -> Bool {
        text.range(of: #"@\s*\$?\s*\d"#, options: .regularExpression) != nil
            || text.range(of: #"(?i)\d\s*/\s*(ea|kg|lb|g|l)\b"#, options: .regularExpression) != nil
    }

    /// Everything to the left of the price, minus the leading quantity and any trailing
    /// tax-class flag ("A", "TFA", "ZRL") that sits after the amount on many receipts.
    private static func itemName(from text: String) -> String? {
        guard let priceRange = text.range(
            of: #"\$?\s*\d+(?:[,\s]\d{3})*[.,]\d{2}"#,
            options: [.regularExpression, .backwards]
        ) else { return nil }

        let name = text[..<priceRange.lowerBound]
            .replacingOccurrences(of: #"^\s*\d{1,3}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d{5,}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*[@x]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // A purchase has a name. Rows that are only numbers are quantities, codes or
        // continuation lines, not items.
        guard name.filter(\.isLetter).count >= 3 else { return nil }
        return name
    }

    private static func quantity(from text: String) -> Int? {
        guard let match = text.range(of: #"^\s*(\d{1,3})\s+\D"#, options: .regularExpression) else {
            return nil
        }
        let digits = text[match].filter(\.isNumber)
        guard let value = Int(digits), value > 0, value <= 999 else { return nil }
        return value
    }
}
