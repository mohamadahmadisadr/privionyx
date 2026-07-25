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
nonisolated struct LineItemExtractor {
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

        let body = Array(lines.prefix(while: { Self.isTotalsRow($0.text, sanitizer: sanitizer) == false }))

        var items: [ReceiptLineItem] = []
        var index = 0
        while index < body.count {
            if let item = lineItem(from: body[index].text) {
                items.append(item)
                index += 1
                continue
            }

            // A description too long for its column wraps, leaving the name on one row and
            // the price alone on the next. Neither row is an item by itself.
            if index + 1 < body.count,
               let item = wrappedItem(nameRow: body[index].text, priceRow: body[index + 1].text) {
                items.append(item)
                index += 2
                continue
            }

            index += 1
        }

        return items
    }

    /// Joins a row carrying only a description to the row beneath carrying only prices.
    /// Where the price row holds several figures the last is the line charge, the ones
    /// before it being the unit price it was derived from.
    private func wrappedItem(nameRow: String, priceRow: String) -> ReceiptLineItem? {
        guard Self.amountExtractor.extractAmounts(in: nameRow).isEmpty,
              Self.latinLetterCount(in: nameRow) >= 3,
              Self.isUnitPriceRow(priceRow) == false,
              priceRow.filter(\.isLetter).count < 3,
              let amount = Self.amountExtractor.extractAmounts(in: priceRow).last,
              amount > 0
        else { return nil }

        guard let name = Self.cleanedItemName(nameRow) else { return nil }
        return ReceiptLineItem(name: name, quantity: Self.quantity(from: nameRow), amount: amount)
    }

    private static func isTotalsRow(_ text: String, sanitizer: ReceiptTextSanitizer) -> Bool {
        let normalized = sanitizer.normalizedTokenLine(text)
        return totalsTokens.contains { MerchantExtractor.containsWord($0, in: normalized) }
    }

    private func lineItem(from text: String) -> ReceiptLineItem? {
        guard Self.isUnitPriceRow(text) == false else { return nil }

        let amounts = Self.amountExtractor.extractAmounts(in: text)
        guard let magnitude = amounts.last, magnitude > 0 else { return nil }

        let normalized = sanitizer.normalizedTokenLine(text)
        guard Self.excludedTokens.contains(where: { MerchantExtractor.containsWord($0, in: normalized) }) == false
        else { return nil }

        // Instant discounts print the minus after the figure — "3.20-A" on a Costco receipt.
        // Read as positive they inflate the item sum past the subtotal they should reconcile
        // against, so the sign has to survive extraction.
        let isCredit = Self.isCreditRow(text)
        let amount = isCredit ? -magnitude : magnitude

        // A credit references the item above it and often carries only product codes, so it
        // has no name of its own. Dropping it for that reason would leave the discount out of
        // the sum entirely, which is the larger error.
        guard let name = Self.itemName(from: text) ?? (isCredit ? "Discount" : nil)
        else { return nil }

        return ReceiptLineItem(name: name, quantity: Self.quantity(from: text), amount: amount)
    }

    /// A trailing minus against the figure, which is how receipts mark an instant discount
    /// or a returned item.
    private static func isCreditRow(_ text: String) -> Bool {
        text.range(of: #"\d[.,]\d{2}\s*-"#, options: .regularExpression) != nil
    }

    /// A per-unit breakdown printed under its item — "4EA @ 2.59/EA", "2 @ 6.99". The
    /// figure is a rate, not a charge, and adding it double-counts against the line above.
    private static func isUnitPriceRow(_ text: String) -> Bool {
        text.range(of: #"@\s*\$?\s*\d"#, options: .regularExpression) != nil
            || text.range(of: #"(?i)\d\s*/\s*(ea|kg|lb|g|l)\b"#, options: .regularExpression) != nil
            // Matched by shape rather than by the separator, because the separator is not
            // reliably read: "6 @ 8.99" came back as "6 е 8.99" with a Cyrillic e.
            || text.range(
                of: #"^\s*\d{1,3}\s*\S{0,2}\s*\$?\s*\d+[.,]\d{2}\s*$"#,
                options: .regularExpression
            ) != nil
    }

    /// Letters in the Latin alphabet only, ignoring digits, marks and other scripts.
    private static func latinLetterCount(in text: String) -> Int {
        text.unicodeScalars.filter { scalar in
            (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
        }.count
    }

    /// Everything to the left of the price, minus the leading quantity and any trailing
    /// tax-class flag ("A", "TFA", "ZRL") that sits after the amount on many receipts.
    private static func itemName(from text: String) -> String? {
        guard let priceRange = text.range(
            of: #"\$?\s*\d+(?:[,\s]\d{3})*[.,]\d{2}"#,
            options: [.regularExpression, .backwards]
        ) else { return nil }

        return cleanedItemName(String(text[..<priceRange.lowerBound]))
    }

    /// Turns the raw text left of the price into a name worth showing.
    ///
    /// Receipts prefix an item with bookkeeping the shopper never cares about: a single-letter
    /// tax class, a quantity, and a product code, in any combination — "E 577 MPEPSI COLA",
    /// "1216/15 CRES SCOPE", "E 3 WHOLE MILK". Each leading token of that kind is peeled off in
    /// turn, but only while a real name remains behind it, so a genuine short lead is never
    /// eaten. What recognition itself got wrong ("MPEPSI") is left alone — that is a
    /// recognition problem, not a formatting one, and guessing at it would invent content.
    ///
    /// Internal so the peeling can be tested directly rather than only through a whole image.
    static func cleanedItemName(_ raw: String) -> String? {
        var name = raw
            .replacingOccurrences(of: #"\s*[@x]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // A leading tax-class letter ("E ", "S ") or a leading code or quantity ("577 ",
        // "1216/15 ", "3 ") — repeatedly, since a row can carry several, but never the last
        // token that still holds the name.
        let leadingNoise = #"^(?:[A-Za-z]|\d[\d/]*)\s+"#
        while name.range(of: leadingNoise, options: .regularExpression) != nil {
            let stripped = name
                .replacingOccurrences(of: leadingNoise, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard Self.latinLetterCount(in: stripped) >= 3 else { break }
            name = stripped
        }

        // A purchase has a name, and on an en-CA/fr-CA/en-US receipt that name is written in
        // Latin letters. Counting any Unicode letter let a row of separator asterisks that
        // OCR'd into Cyrillic ("химжижиии") claim a neighbouring price as an item. Accented
        // French names still qualify on their remaining ASCII letters.
        guard Self.latinLetterCount(in: name) >= 3 else { return nil }
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
