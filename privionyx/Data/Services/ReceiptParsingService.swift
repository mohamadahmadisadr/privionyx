import Foundation

struct ReceiptParsingService {
    private let mlExtractor: CoreMLReceiptExtractionService?

    init(mlExtractor: CoreMLReceiptExtractionService? = nil) {
        self.mlExtractor = mlExtractor
    }

    func parse(rawText: String) async -> ParsedReceiptData {
        let cleanedLines = rawText
            .components(separatedBy: .newlines)
            .map(cleanedReceiptLine)
            .filter { $0.isEmpty == false }

        return await parse(rawText: rawText, structuredLines: cleanedLines, positionedLines: [])
    }

    func parse(ocrResult: OCRResult) async -> ParsedReceiptData {
        let structuredLines = ocrResult.lines
            .map { cleanedReceiptLine($0.text) }
            .filter { $0.isEmpty == false }
        return await parse(rawText: ocrResult.rawText, structuredLines: structuredLines, positionedLines: ocrResult.lines)
    }

    private func parse(rawText: String, structuredLines: [String], positionedLines: [OCRTextLine]) async -> ParsedReceiptData {
        let mlExtraction = positionedLines.isEmpty ? nil : mlExtractor?.extract(from: positionedLines)
        let merchant = mlExtraction?.merchant ?? extractMerchant(from: structuredLines) ?? "Unknown Merchant"
        let tax = extractValue(from: structuredLines, positionedLines: positionedLines, matching: ["tax", "hst", "gst", "vat", "sales tax", "tps", "tvq"])
        let tip = extractValue(from: structuredLines, positionedLines: positionedLines, matching: ["tip", "gratuity", "service", "service tip"])
        let explicitSubtotal = extractExplicitSubtotal(from: structuredLines, positionedLines: positionedLines)
        let lineItems: [ReceiptLineItem] = []
        let amountCandidates = extractAmountCandidates(from: structuredLines, positionedLines: positionedLines)
        let amount = mlExtraction?.amount ?? selectBestAmount(
            from: amountCandidates,
            explicitSubtotal: explicitSubtotal,
            tax: tax,
            tip: tip,
            lineItems: lineItems
        ) ?? .zero
        let subtotal = mlExtraction?.subtotal ?? explicitSubtotal ?? deriveSubtotal(total: amount, tax: tax, tip: tip)
        let resolvedTax = mlExtraction?.tax ?? tax
        let resolvedTip = mlExtraction?.tip ?? tip
        let date = mlExtraction?.date ?? extractDate(from: structuredLines) ?? .now
        let category = categorize(merchant: merchant, lines: structuredLines)
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

    private func extractAmount(from lines: [String], positionedLines: [OCRTextLine]) -> Double? {
        extractAmountCandidates(from: lines, positionedLines: positionedLines)
            .max { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.amount < rhs.amount
                }
                return lhs.score < rhs.score
            }?
            .amount
    }

    private func extractAmountCandidates(from lines: [String], positionedLines: [OCRTextLine]) -> [(amount: Double, score: Int)] {
        if positionedLines.isEmpty == false,
           let summaryCandidates = extractSummaryAmountCandidates(from: positionedLines),
           summaryCandidates.isEmpty == false {
            return summaryCandidates
        }

        let sourceLines = positionedLines.isEmpty ? lines.enumerated().map { (text: $0.element, index: $0.offset, geometry: nil as OCRTextLine?) } : positionedLines.enumerated().map { (text: $0.element.text, index: $0.offset, geometry: Optional($0.element)) }

        return sourceLines.flatMap { source in
            extractAmounts(in: source.text).map { amount in
                (
                    amount: amount,
                    score: amountScore(
                        for: source.text,
                        index: source.index,
                        amount: amount,
                        totalLines: lines.count,
                        geometry: source.geometry
                    )
                )
            }
        }
    }

    private func extractAmounts(in line: String) -> [Double] {
        let normalizedLine = line
            .replacingOccurrences(of: #"(?<=\d)\s+(?=\d{2}\b)"#, with: ".", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)\s*[\.,]\s*(?=\d{2}\b)"#, with: ".", options: .regularExpression)
        let pattern = #"\$?\s*\d+(?:[,\s]\d{3})*(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(normalizedLine.startIndex..<normalizedLine.endIndex, in: normalizedLine)
        return regex.matches(in: normalizedLine, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: normalizedLine) else { return nil }
            return parseCurrencyValue(String(normalizedLine[matchRange]))
        }
    }

    private func extractValue(from lines: [String], positionedLines: [OCRTextLine], matching tokens: [String]) -> Double? {
        if positionedLines.isEmpty == false,
           let positionedMatch = extractValueFromStructuredTotals(in: positionedLines, matching: tokens) {
            return positionedMatch
        }

        if let regexMatch = extractValueUsingRegex(from: lines, matching: tokens) {
            return regexMatch
        }

        let sources = positionedLines.isEmpty ? lines.map { ($0, nil as OCRTextLine?) } : positionedLines.map { ($0.text, Optional($0)) }

        let candidates = sources.compactMap { source -> (Double, Double)? in
            let normalizedLine = normalizedTokenLine(source.0)
            guard tokens.contains(where: { token in
                normalizedLine.contains(normalizedTokenLine(token))
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

    private func extractValueUsingRegex(from lines: [String], matching tokens: [String]) -> Double? {
        let tokenPattern = tokens
            .map { NSRegularExpression.escapedPattern(for: normalizedTokenLine($0)) }
            .joined(separator: "|")
        let pattern = #"(?i)(?:\#(tokenPattern))\D{0,12}(\d+(?:[,\s]\d{3})*(?:[.,]\d{2}))"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        for line in lines {
            let normalizedLine = normalizedTokenLine(line)
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

    private func extractExplicitSubtotal(from lines: [String], positionedLines: [OCRTextLine]) -> Double? {
        extractValue(from: lines, positionedLines: positionedLines, matching: ["subtotal", "sub total", "sub-total", "net sales"])
    }

    private func extractValueFromAdjacentLine(from lines: [String], matching tokens: [String]) -> Double? {
        let normalizedTokens = tokens.map(normalizedTokenLine)
        let indexedLines = Array(lines.enumerated())

        for (index, line) in indexedLines {
            let normalizedLine = normalizedTokenLine(line)
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

    private func deriveSubtotal(total: Double, tax: Double?, tip: Double?) -> Double? {
        let deductions = (tax ?? 0) + (tip ?? 0)
        guard total > 0, deductions > 0 else { return nil }

        let derivedSubtotal = total - deductions
        return derivedSubtotal > 0 ? derivedSubtotal : nil
    }

    private func extractDate(from lines: [String]) -> Date? {
        let patterns = [
            "MM/dd/yyyy", "MM/dd/yy", "yyyy-MM-dd", "dd/MM/yyyy", "dd/MM/yy",
            "MM-dd-yyyy", "MM-dd-yy", "dd-MM-yyyy", "dd-MM-yy",
            "MMM d yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"
        ]
        let formatter = makePOSIXFormatter()

        for line in lines {
            let sanitizedLine = line
                .replacingOccurrences(of: #"(?i)\b(o|O)(?=\d)"#, with: "0", options: .regularExpression)
                .replacingOccurrences(of: #"(?<=\d)(o|O)\b"#, with: "0", options: .regularExpression)
                .replacingOccurrences(of: ",", with: " ")
            let slashCandidates = sanitizedLine.split(whereSeparator: \.isWhitespace)

            for candidate in slashCandidates {
                for pattern in patterns {
                    formatter.dateFormat = pattern
                    if let date = formatter.date(from: String(candidate)) {
                        return date
                    }
                }
            }

            let joinedCandidates = candidateDateSegments(from: sanitizedLine)
            for candidate in joinedCandidates {
                for pattern in patterns {
                    formatter.dateFormat = pattern
                    if let date = formatter.date(from: candidate) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func categorize(merchant: String, lines: [String]) -> ReceiptCategory {
        let joined = ([merchant] + lines).joined(separator: " ").lowercased()
        let categoryKeywords: [ReceiptCategory: [String]] = [
            .gas: ["shell", "petro", "petro-canada", "esso", "fuel", "chevron", "exxon", "mobil", "bp", "pump", "gasoline"],
            .grocery: ["whole foods", "trader joe", "aldi", "metro", "loblaws", "no frills", "market", "grocery", "supermarket", "kroger", "safeway", "produce"],
            .dining: ["coffee", "restaurant", "cafe", "tim hortons", "starbucks", "pizza", "burger", "grill", "bar", "bakery", "mcdonald"],
            .travel: ["air", "airlines", "hotel", "uber", "lyft", "flight", "airport", "booking", "airbnb"],
            .utilities: ["power", "water", "electric", "energy", "utility", "internet", "wireless", "telecom", "hydro"],
            .shopping: ["target", "walmart", "costco", "canadian tire", "store", "shopping", "retail", "amazon", "mall"]
        ]

        let rankedCategories = categoryKeywords.map { category, keywords in
            let score = keywords.reduce(into: 0) { partialResult, keyword in
                if joined.contains(keyword) {
                    partialResult += keyword.contains(" ") ? 4 : 2
                }
            }
            return (category: category, score: score)
        }

        return rankedCategories.max(by: { lhs, rhs in lhs.score < rhs.score })?.score ?? 0 > 0
            ? rankedCategories.max(by: { lhs, rhs in lhs.score < rhs.score })?.category ?? .shopping
            : .shopping
    }

    private func extractMerchant(from lines: [String]) -> String? {
        if let knownMerchant = knownMerchant(in: lines) {
            return knownMerchant
        }

        let candidates = lines.prefix(8)
            .enumerated()
            .compactMap { index, line -> (String, Int)? in
                let cleanedLine = cleanedMerchantLine(line)
                guard cleanedLine.rangeOfCharacter(from: .letters) != nil else { return nil }

                let lowercased = cleanedLine.lowercased()
                let blockedTokens = [
                    "total", "subtotal", "tax", "hst", "gst", "cash", "change", "invoice",
                    "receipt", "visa", "mastercard", "debit", "amount", "date", "time",
                    "terminal", "approval", "transaction", "merchant id", "auth"
                ]

                guard blockedTokens.contains(where: lowercased.contains) == false else {
                    return nil
                }

                let lettersOnly = cleanedLine.filter(\.isLetter).count
                let digitsOnly = cleanedLine.filter(\.isNumber).count
                guard lettersOnly >= 3, digitsOnly <= max(3, lettersOnly / 2) else { return nil }

                var score = max(0, 20 - (index * 3))
                if cleanedLine == cleanedLine.uppercased(), lettersOnly >= 4 {
                    score += 8
                }
                if lowercased.contains("store") || lowercased.contains("market") {
                    score += 2
                }
                if cleanedLine.count <= 28 {
                    score += 4
                }

                return (cleanedLine, score)
            }

        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    private func amountScore(for line: String, index: Int, amount: Double, totalLines: Int, geometry: OCRTextLine?) -> Int {
        let lowercased = line.lowercased()
        var score = Int(amount.rounded())

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

    private func selectBestAmount(
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

    private func extractValueFromStructuredTotals(in lines: [OCRTextLine], matching tokens: [String]) -> Double? {
        let normalizedTokens = tokens.map(normalizedTokenLine)
        let summaryLines = summaryRelevantLines(from: lines)
        let candidates = bottomAmountCandidates(from: summaryLines).filter { candidate in
            let normalized = normalizedTokenLine(candidate.line.text)
            return normalizedTokens.contains(where: normalized.contains)
        }

        if let directMatch = candidates.max(by: { $0.score < $1.score })?.amount {
            return directMatch
        }

        if tokens.contains(where: { ["tax", "hst", "gst", "vat", "sales tax", "tps", "tvq"].contains($0) }),
           let subtotal = extractValueUsingSummaryPattern(in: summaryLines, matching: ["subtotal", "sub total", "sub-total", "net sales"]),
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
        let normalized = normalizedTokenLine(line.text)
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
            let normalized = normalizedTokenLine(line.text)
            let hasToken = summaryTokens.contains(where: normalized.contains)
            let hasAmount = extractAmounts(in: line.text).isEmpty == false
            return hasToken && hasAmount ? index : nil
        }

        guard summaryIndices.isEmpty == false else { return lines }

        let start = max((summaryIndices.min() ?? 0) - 1, 0)
        var end = min((summaryIndices.max() ?? 0) + 2, lines.count - 1)

        for index in (summaryIndices.max() ?? start)..<lines.count {
            let normalized = normalizedTokenLine(lines[index].text)
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

    private func knownMerchant(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ").lowercased()
        let aliases: [(name: String, patterns: [String])] = [
            ("Canadian Tire", ["canadian tire", "canadiantire", "ctr", "ct money"]),
            ("Costco", ["costco", "costco wholesale"]),
            ("Walmart", ["walmart", "wal-mart"]),
            ("Tim Hortons", ["tim hortons", "tim's", "tims"]),
            ("Petro-Canada", ["petro-canada", "petro canada"]),
            ("Shell", ["shell"]),
            ("Esso", ["esso"]),
            ("Metro", ["metro"]),
            ("No Frills", ["no frills", "nofrills"]),
            ("Loblaws", ["loblaws"]),
            ("Amazon", ["amazon"])
        ]

        let ranked = aliases.compactMap { alias -> (String, Int)? in
            let score = alias.patterns.reduce(into: 0) { partial, pattern in
                if joined.contains(pattern) {
                    partial += pattern.contains(" ") ? 10 : 6
                }
            }
            return score > 0 ? (alias.name, score) : nil
        }

        return ranked.max(by: { $0.1 < $1.1 })?.0
    }

    private func candidateDateSegments(from line: String) -> [String] {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3 else { return [] }

        var segments: [String] = []

        for index in 0..<(words.count - 2) {
            segments.append(words[index...min(index + 2, words.count - 1)].joined(separator: " "))
        }

        return segments
    }

    private func makePOSIXFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }

    private func normalizedTokenLine(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedReceiptLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"[\u{00A0}\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[oO](?=\d)"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[lI](?=\d)"#, with: "1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\$)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedMerchantLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\W+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func parseCurrencyValue(_ rawValue: String) -> Double? {
        var value = rawValue
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "s", with: "5")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
