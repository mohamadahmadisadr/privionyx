import Foundation

nonisolated struct AmountExtractor {
    private let sanitizer: ReceiptTextSanitizer

    init(sanitizer: ReceiptTextSanitizer = ReceiptTextSanitizer()) {
        self.sanitizer = sanitizer
    }

    func extractAmount(from lines: [String], positionedLines: [OCRTextLine]) -> Double? {
        extractAmountCandidates(from: lines, positionedLines: positionedLines)
            .max { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.amount < rhs.amount
                }
                return lhs.score < rhs.score
            }?
            .amount
    }

    func extractAmountCandidates(from lines: [String], positionedLines: [OCRTextLine]) -> [(amount: Double, score: Int)] {
        if positionedLines.isEmpty == false,
           let summaryCandidates = extractSummaryAmountCandidates(from: positionedLines),
           summaryCandidates.isEmpty == false {
            return summaryCandidates
        }

        let sourceLines = positionedLines.isEmpty ? lines.enumerated().map { (text: $0.element, index: $0.offset, geometry: nil as OCRTextLine?) } : positionedLines.enumerated().map { (text: $0.element.text, index: $0.offset, geometry: Optional($0.element)) }

        let scored = sourceLines.flatMap { source in
            extractAmounts(in: source.text).map { amount in
                (
                    amount: amount,
                    score: amountScore(
                        for: source.text,
                        index: source.index,
                        totalLines: lines.count,
                        geometry: source.geometry
                    )
                )
            }
        }

        return Self.rankedByMagnitude(scored)
    }

    /// How much "the total is usually the largest figure on the receipt" is worth.
    ///
    /// Below the `total` label bonus on purpose, so a labelled figure outranks a larger
    /// unlabelled one whatever the receipt's size.
    private static let magnitudeWeight = 60.0

    /// Adds the size prior as a share of the largest candidate rather than as the amount.
    ///
    /// `amountScore` used to start at the amount in dollars, which made this prior worth
    /// nothing on a small receipt and more than every label combined on a large one — the
    /// same three lines ("TOTAL", "CASH", "CHANGE") extracted correctly at $12.50 and
    /// returned the cash tendered at $420. Ranking against the other candidates makes the
    /// weighting mean the same thing at any size.
    private static func rankedByMagnitude(_ candidates: [(amount: Double, score: Int)]) -> [(amount: Double, score: Int)] {
        guard let largest = candidates.map(\.amount).max(), largest > 0 else { return candidates }

        return candidates.map { candidate in
            let share = candidate.amount / largest
            return (amount: candidate.amount, score: candidate.score + Int((share * magnitudeWeight).rounded()))
        }
    }

    func extractAmounts(in line: String) -> [Double] {
        signedAmounts(in: line).map(abs)
    }

    /// The amounts on a line, keeping the minus sign of any written negative.
    ///
    /// Everything that reads figures off a receipt wants magnitudes — a discount row and a
    /// tax row are both just numbers to the scorer — so `extractAmounts` drops the sign.
    /// Only `isRefund` needs it, to tell a return from a purchase.
    func signedAmounts(in line: String) -> [Double] {
        let normalizedLine = line
            // Receipts print "12 34" for 12.34, but a run of digits followed by a date or
            // time separator is an identifier, not a price. "2026 05:43PM" became a 2026.05
            // total; "TAXINV:001-1541798 03/03/18" became 1541798.03.
            .replacingOccurrences(
                of: #"(?<=\d)\s+(?=\d{2}\b)(?!\d{2}\s*[:./-]\d)"#,
                with: ".",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"(?<=\d)\s*[\.,]\s*(?=\d{2}\b)"#, with: ".", options: .regularExpression)
        // A figure fused to letters is an identifier, not a price. The footer of an LCBO
        // receipt prints a version string that recognition returned as "V124.03", which is
        // indistinguishable from currency by shape alone and won the total on a receipt
        // whose real total is 33.25.
        let pattern = #"(?<![A-Za-z0-9])(-\s*)?\$?\s*\d+(?:[,\s]\d{3})*(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(normalizedLine.startIndex..<normalizedLine.endIndex, in: normalizedLine)
        return regex.matches(in: normalizedLine, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: normalizedLine) else { return nil }
            return parseCurrencyValue(String(normalizedLine[matchRange]))
        }
    }

    /// True when the receipt's bottom line is printed negative — a return rather than a sale.
    ///
    /// Only the total's own row is consulted, and only by word. A negative figure among the
    /// items is an adjustment to a purchase that still cost money: a member discount, a
    /// penny-rounding line. "subtotal" is one word, so it does not match either — a receipt
    /// whose bottom line is missing should not be read as a refund on the strength of the row
    /// above it.
    func isRefund(from lines: [String], positionedLines: [OCRTextLine]) -> Bool {
        let sources = positionedLines.isEmpty ? lines : positionedLines.map(\.text)

        return sources.contains { line in
            let normalized = sanitizer.normalizedTokenLine(line)
            guard Self.totalsBlockTokens.contains(where: { MerchantExtractor.containsWord($0, in: normalized) })
            else { return false }
            // "TOTAL SAVINGS" and "TOTAL REWARDS" carry the word without being the bottom
            // line, and both are routinely printed negative.
            guard Self.notTheBottomLine.contains(where: normalized.contains) == false else { return false }
            guard let last = signedAmounts(in: line).last else { return false }
            return last < 0
        }
    }

    private static let totalsBlockTokens = ["total", "amount due", "balance due"]

    private static let notTheBottomLine = [
        "saved", "savings", "discount", "reward", "loyalty", "points", "change"
    ]

    func extractValue(from lines: [String], positionedLines: [OCRTextLine], matching tokens: [String]) -> Double? {
        if positionedLines.isEmpty == false,
           let positionedMatch = extractValueFromStructuredTotals(in: positionedLines, matching: tokens) {
            return positionedMatch
        }

        if let regexMatch = extractValueUsingRegex(from: lines, matching: tokens) {
            return regexMatch
        }

        let sources = positionedLines.isEmpty ? lines.map { ($0, nil as OCRTextLine?) } : positionedLines.map { ($0.text, Optional($0)) }

        let candidates = sources.compactMap { source -> (Double, Double)? in
            let normalizedLine = sanitizer.normalizedTokenLine(source.0)
            guard tokens.contains(where: { token in
                normalizedLine.contains(sanitizer.normalizedTokenLine(token))
            }) else { return nil }

            let amounts = extractAmounts(in: source.0)
            guard amounts.isEmpty == false else { return nil }
            let base = amounts.last ?? 0
            let layoutBonus = source.1.map { Double($0.maxX) } ?? 0

            if normalizedLine.contains("total"), let nonTotalAmount = amounts.dropLast().last {
                return (nonTotalAmount, layoutBonus)
            }

            return (base, layoutBonus)
        }

        if let directCandidate = candidates.max(by: { ($0.0 + $0.1) < ($1.0 + $1.1) })?.0 {
            return directCandidate
        }

        return extractValueFromAdjacentLine(from: lines, matching: tokens)
    }

    func extractExplicitSubtotal(from lines: [String], positionedLines: [OCRTextLine]) -> Double? {
        extractValue(from: lines, positionedLines: positionedLines, matching: Self.subtotalTokens)
    }

    /// Dual-tax jurisdictions print each tax on its own line (TPS + TVQ in Quebec,
    /// GST + PST in several provinces). The draft carries one tax field, so those have to
    /// be summed — taking the largest, as the generic value lookup does, silently drops
    /// the other one. An explicit aggregate line wins outright, since adding it to its own
    /// components would double count.
    func extractTax(from lines: [String], positionedLines: [OCRTextLine]) -> Double? {
        let taxLines = taxLineAmounts(from: lines, positionedLines: positionedLines)

        guard taxLines.isEmpty == false else {
            // No labelled tax line at all — fall back to the geometry-aware lookup, which
            // can still derive tax from the gap between subtotal and total.
            return extractValue(from: lines, positionedLines: positionedLines, matching: Self.taxTokens)
        }

        if let aggregate = taxLines.first(where: \.isAggregate)?.amount {
            return aggregate
        }

        return taxLines.map(\.amount).reduce(0, +)
    }

    private func taxLineAmounts(
        from lines: [String],
        positionedLines: [OCRTextLine]
    ) -> [(amount: Double, isAggregate: Bool)] {
        let sources = positionedLines.isEmpty ? lines : positionedLines.map(\.text)
        let normalizedTokens = Self.taxTokens.map(sanitizer.normalizedTokenLine)

        return sources.compactMap { line in
            let normalized = sanitizer.normalizedTokenLine(line)
            // Word boundaries matter more here than elsewhere: a substring match would let
            // "TAXABLE ITEMS 42.00" contribute its line total to the tax sum.
            guard normalizedTokens.contains(where: { MerchantExtractor.containsWord($0, in: normalized) })
            else { return nil }
            guard let amount = extractAmounts(in: line).last else { return nil }
            return (amount: amount, isAggregate: MerchantExtractor.containsWord("total", in: normalized))
        }
    }

    static let taxTokens = ["tax", "hst", "gst", "vat", "sales tax", "tps", "tvq", "qst", "pst"]

    static let subtotalTokens = [
        "subtotal", "sub total", "sub-total", "net sales", "sous-total", "sous total"
    ]

    func deriveSubtotal(total: Double, tax: Double?, tip: Double?) -> Double? {
        let deductions = (tax ?? 0) + (tip ?? 0)
        guard total > 0, deductions > 0 else { return nil }

        let derivedSubtotal = total - deductions
        return derivedSubtotal > 0 ? derivedSubtotal : nil
    }

    func selectBestAmount(
        from candidates: [(amount: Double, score: Int)],
        explicitSubtotal: Double?,
        tax: Double?,
        tip: Double?,
        lineItems: [ReceiptLineItem]
    ) -> Double? {
        guard candidates.isEmpty == false else { return nil }

        let lineItemSum = lineItems.map(\.amount).reduce(0, +)
        let expectedFromSubtotal = explicitSubtotal.map { $0 + (tax ?? 0) + (tip ?? 0) }
        let expectedFromItems = lineItemSum > 0 ? lineItemSum + (tax ?? 0) + (tip ?? 0) : nil

        return candidates
            .map { candidate in
                var score = candidate.score

                if let expectedFromSubtotal {
                    score -= Int(abs(candidate.amount - expectedFromSubtotal) * 12)
                }

                if let expectedFromItems {
                    score -= Int(abs(candidate.amount - expectedFromItems) * 6)
                    if candidate.amount > expectedFromItems * 2.2 {
                        score -= 120
                    }
                }

                return (amount: candidate.amount, score: score)
            }
            .max(by: { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.amount < rhs.amount
                }
                return lhs.score < rhs.score
            })?
            .amount
    }

    private func extractValueUsingRegex(from lines: [String], matching tokens: [String]) -> Double? {
        let tokenPattern = tokens
            .map { NSRegularExpression.escapedPattern(for: sanitizer.normalizedTokenLine($0)) }
            .joined(separator: "|")
        let pattern = #"(?i)(?:\#(tokenPattern))\D{0,12}(\d+(?:[,\s]\d{3})*(?:[.,]\d{2}))"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        for line in lines {
            let normalizedLine = sanitizer.normalizedTokenLine(line)
            let range = NSRange(normalizedLine.startIndex..<normalizedLine.endIndex, in: normalizedLine)
            guard let match = regex.firstMatch(in: normalizedLine, range: range),
                  let valueRange = Range(match.range(at: 1), in: normalizedLine) else {
                continue
            }

            if let parsed = parseCurrencyValue(String(normalizedLine[valueRange])) {
                return parsed
            }
        }

        return nil
    }

    private func extractValueFromAdjacentLine(from lines: [String], matching tokens: [String]) -> Double? {
        let normalizedTokens = tokens.map(sanitizer.normalizedTokenLine)
        let indexedLines = Array(lines.enumerated())

        for (index, line) in indexedLines {
            let normalizedLine = sanitizer.normalizedTokenLine(line)
            guard normalizedTokens.contains(where: normalizedLine.contains) else { continue }

            for neighborIndex in [index + 1, index - 1] where lines.indices.contains(neighborIndex) {
                let amounts = extractAmounts(in: lines[neighborIndex])
                if let amount = amounts.last {
                    return amount
                }
            }
        }

        return nil
    }

    /// Scores what the *line* says about the figure. The figure's own size is added later,
    /// by `rankedByMagnitude`, once every candidate is known and it can be weighed against
    /// them instead of in dollars.
    private func amountScore(for line: String, index: Int, totalLines: Int, geometry: OCRTextLine?) -> Int {
        let lowercased = line.lowercased()
        var score = 0

        let positiveSignals = [
            ("grand total", 100),
            ("total", 80),
            ("amount due", 70),
            ("balance due", 65),
            ("balance", 40),
            ("net total", 65),
            ("purchase", 20),
            ("paid", 30)
        ]

        let negativeSignals = [
            ("subtotal", -45),
            ("sub total", -45),
            ("tax", -35),
            ("vat", -35),
            ("change", -40),
            ("saved", -80),
            ("savings", -80),
            ("ct money", -95),
            ("triangle", -80),
            ("loyalty", -70),
            ("reward", -70),
            ("discount", -30),
            ("item", -20),
            ("auth", -20),
            ("approval", -20),
            ("card", -15)
        ]

        for (token, weight) in positiveSignals where lowercased.contains(token) {
            score += weight
        }

        for (token, weight) in negativeSignals where lowercased.contains(token) {
            score += weight
        }

        if index >= max(totalLines - 4, 0) {
            score += 10
        }

        if let geometry {
            if geometry.maxX > 0.72 {
                score += 16
            }
            if geometry.midY < 0.28 {
                score += 18
            }
            if geometry.midY > 0.82 {
                score -= 12
            }
        }

        return score
    }

    private func extractBottomTotal(from lines: [OCRTextLine]) -> (amount: Double, score: Int)? {
        let candidates = bottomAmountCandidates(from: summaryRelevantLines(from: lines))
        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return nil
        }
        return (amount: best.amount, score: best.score)
    }

    private func extractSummaryAmountCandidates(from lines: [OCRTextLine]) -> [(amount: Double, score: Int)]? {
        let summaryLines = summaryRelevantLines(from: lines)
        let candidates = bottomAmountCandidates(from: summaryLines).map { candidate in
            (amount: candidate.amount, score: candidate.score)
        }
        return candidates.isEmpty ? nil : candidates
    }

    private func extractValueFromStructuredTotals(in lines: [OCRTextLine], matching tokens: [String]) -> Double? {
        let normalizedTokens = tokens.map(sanitizer.normalizedTokenLine)
        let summaryLines = summaryRelevantLines(from: lines)
        let candidates = bottomAmountCandidates(from: summaryLines).filter { candidate in
            let normalized = sanitizer.normalizedTokenLine(candidate.line.text)
            return normalizedTokens.contains(where: normalized.contains)
        }

        if let directMatch = candidates.max(by: { $0.score < $1.score })?.amount {
            return directMatch
        }

        if tokens.contains(where: { Self.taxTokens.contains($0) }),
           let subtotal = extractValueUsingSummaryPattern(in: summaryLines, matching: Self.subtotalTokens),
           let total = extractValueUsingSummaryPattern(in: summaryLines, matching: ["total", "amount due", "balance due"]),
           total > subtotal {
            let derivedTax = total - subtotal
            return derivedTax > 0.01 ? derivedTax : nil
        }

        return nil
    }

    private func bottomAmountCandidates(from lines: [OCRTextLine]) -> [(line: OCRTextLine, amount: Double, score: Int)] {
        lines.compactMap { line in
            guard line.midY < 0.42, line.maxX > 0.58 else { return nil }
            let amounts = extractAmounts(in: line.text)
            guard let amount = amounts.last else { return nil }
            let score = bottomAmountScore(for: line, amount: amount)
            return (line: line, amount: amount, score: score)
        }
    }

    private func bottomAmountScore(for line: OCRTextLine, amount: Double) -> Int {
        let normalized = sanitizer.normalizedTokenLine(line.text)
        var score = Int((amount * 10).rounded())

        if normalized.contains("grand total") { score += 160 }
        if normalized.contains("amount due") { score += 140 }
        if normalized.contains("balance due") { score += 125 }
        if normalized.contains("total") { score += 110 }
        if normalized.contains("net total") { score += 95 }
        if normalized == "total" || normalized.hasPrefix("total ") || normalized.contains(" total ") { score += 130 }
        if normalized.contains("paid") { score += 50 }

        if normalized.contains("subtotal") { score -= 65 }
        if normalized.contains("sub total") { score -= 65 }
        if normalized.contains("tax") { score -= 70 }
        if normalized.contains("hst") || normalized.contains("gst") || normalized.contains("vat") || normalized.contains("tvq") { score -= 70 }
        if normalized.contains("tip") || normalized.contains("gratuity") { score -= 55 }
        if normalized.contains("change") { score -= 80 }
        if normalized.contains("saved") || normalized.contains("savings") { score -= 110 }
        if normalized.contains("ct money") || normalized.contains("triangle") { score -= 130 }
        if normalized.contains("loyalty") || normalized.contains("reward") { score -= 110 }
        if normalized.contains("cash") || normalized.contains("debit") || normalized.contains("credit") || normalized.contains("visa") || normalized.contains("mastercard") { score -= 24 }

        score += Int(line.maxX * 22)
        score += Int((1 - line.midY) * 40)
        return score
    }

    private func summaryRelevantLines(from lines: [OCRTextLine]) -> [OCRTextLine] {
        guard lines.isEmpty == false else { return [] }

        let summaryTokens = [
            "subtotal", "sub total", "sub-total", "net sales",
            "tax", "hst", "gst", "vat", "sales tax", "tps", "tvq",
            "tip", "gratuity",
            "total", "amount due", "balance due"
        ]

        let paymentTokens = ["debit", "credit", "visa", "mastercard", "interac", "auth", "approval", "change"]

        let indexed = Array(lines.enumerated())
        let summaryIndices = indexed.compactMap { index, line -> Int? in
            let normalized = sanitizer.normalizedTokenLine(line.text)
            let hasToken = summaryTokens.contains(where: normalized.contains)
            let hasAmount = extractAmounts(in: line.text).isEmpty == false
            return hasToken && hasAmount ? index : nil
        }

        guard summaryIndices.isEmpty == false else { return lines }

        let start = max((summaryIndices.min() ?? 0) - 1, 0)
        var end = min((summaryIndices.max() ?? 0) + 2, lines.count - 1)

        for index in (summaryIndices.max() ?? start)..<lines.count {
            let normalized = sanitizer.normalizedTokenLine(lines[index].text)
            if paymentTokens.contains(where: normalized.contains) {
                end = max(index - 1, start)
                break
            }
            if normalized.contains("saved") || normalized.contains("ct money") || normalized.contains("triangle") {
                end = max(index - 1, start)
                break
            }
        }

        return Array(lines[start...end])
    }

    private func extractValueUsingSummaryPattern(in lines: [OCRTextLine], matching tokens: [String]) -> Double? {
        let textLines = lines.map(\.text)
        return extractValueUsingRegex(from: textLines, matching: tokens)
            ?? extractValue(from: textLines, positionedLines: [], matching: tokens)
    }

    private func parseCurrencyValue(_ rawValue: String) -> Double? {
        // Only `$`, digits and separators can reach here: both callers pass a substring
        // matched by a digits-only pattern. This used to also substitute S→5 and O→0, which
        // read as OCR repair but could never fire — glyph confusion is handled upstream,
        // where the text still has letters in it.
        var value = rawValue
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")

        if value.contains(","), value.contains(".") {
            let commaIndex = value.lastIndex(of: ",") ?? value.startIndex
            let dotIndex = value.lastIndex(of: ".") ?? value.startIndex
            if commaIndex > dotIndex {
                value = value.replacingOccurrences(of: ".", with: "")
                value = value.replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if value.contains(",") {
            value = value.replacingOccurrences(of: ",", with: ".")
        }

        return Double(value)
    }
}
