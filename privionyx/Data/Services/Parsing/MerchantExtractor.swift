import Foundation

struct MerchantExtractor {
    /// The merchant name lives in the letterhead. Searching the whole receipt lets a
    /// payment-network name or a footer mention outrank the actual header line.
    private static let headerDepth = 8

    func extractMerchant(from lines: [String]) -> String? {
        let header = Array(lines.prefix(Self.headerDepth))

        if let knownMerchant = knownMerchant(in: header) {
            return knownMerchant
        }

        return heuristicMerchant(in: header)
    }

    private func knownMerchant(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ").lowercased()

        let ranked = Self.aliases.compactMap { alias -> (String, Int)? in
            let score = alias.patterns.reduce(into: 0) { partial, pattern in
                guard Self.containsWord(pattern, in: joined) else { return }
                partial += pattern.contains(" ") ? 10 : 6
            }
            return score > 0 ? (alias.name, score) : nil
        }

        return ranked.max(by: { $0.1 < $1.1 })?.0
    }

    private func heuristicMerchant(in lines: [String]) -> String? {
        let candidates = lines
            .enumerated()
            .compactMap { index, line -> (String, Int)? in
                let cleanedLine = cleanedMerchantLine(line)
                guard cleanedLine.rangeOfCharacter(from: .letters) != nil else { return nil }

                let lowercased = cleanedLine.lowercased()
                guard Self.blockedTokens.contains(where: lowercased.contains) == false else {
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

    /// Matches only at word boundaries. Plain `contains` made "metro" claim
    /// "Metropolitan Bakery", and "shell" would claim anything containing "shellfish".
    static func containsWord(_ pattern: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        return text.range(of: #"\b\#(escaped)\b"#, options: .regularExpression) != nil
    }

    private func cleanedMerchantLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\W+"#, with: "", options: .regularExpression)
            // A store number is not part of the name: "STARBUCKS #1147" -> "STARBUCKS".
            .replacingOccurrences(of: #"\s*#\s*\d+\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?i)\s+(store|str|unit|loc)\.?\s*#?\s*\d+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Header lines that are never the merchant. Greeting banners sit above the name on
    /// many receipts and otherwise win the position score outright.
    private static let blockedTokens = [
        "total", "subtotal", "tax", "hst", "gst", "cash", "change", "invoice",
        "receipt", "visa", "mastercard", "debit", "amount", "date", "time",
        "terminal", "approval", "transaction", "merchant id", "auth",
        "welcome", "thank you", "merci", "bienvenue", "customer copy",
        "hours", "www.", "http", "tel:", "phone"
    ]

    private static let aliases: [(name: String, patterns: [String])] = [
        ("Canadian Tire", ["canadian tire", "canadiantire", "ct money"]),
        ("Costco", ["costco", "costco wholesale"]),
        ("Walmart", ["walmart", "wal-mart"]),
        ("Tim Hortons", ["tim hortons", "tims"]),
        ("Petro-Canada", ["petro-canada", "petro canada"]),
        ("Shell", ["shell"]),
        ("Esso", ["esso"]),
        ("Metro", ["metro"]),
        ("No Frills", ["no frills", "nofrills"]),
        ("Loblaws", ["loblaws"]),
        ("Amazon", ["amazon"])
    ]
}
