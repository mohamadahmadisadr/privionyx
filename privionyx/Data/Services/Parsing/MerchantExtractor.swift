import Foundation

struct MerchantExtractor {
    /// The merchant name lives in the letterhead. Searching the whole receipt lets a
    /// payment-network name or a footer mention outrank the actual header line.
    private static let headerDepth = 8

    /// How far up from the bottom the closing sign-off is looked for. Matches `headerDepth`
    /// because the shape is the same, read from the other end.
    private static let footerDepth = 8

    func extractMerchant(from lines: [String]) -> String? {
        let header = Array(lines.prefix(Self.headerDepth))

        if let knownMerchant = knownMerchant(in: header) {
            return knownMerchant
        }

        if let heuristic = heuristicMerchant(in: header) {
            return heuristic
        }

        // Only once the letterhead has produced nothing. On a terminal-printed slip the top
        // of the receipt is boilerplate and the shop's name appears once, in the sign-off.
        return signOffMerchant(in: lines)
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
                guard let candidate = merchantCandidate(line) else { return nil }
                // Position only means anything read from the top, so it is added here rather
                // than in the shared scoring — the footer scan has no use for it.
                return (candidate.name, candidate.score + max(0, 20 - (index * 3)))
            }

        // Below this the best candidate is not a name, just the least bad line left over.
        // A receipt that carries no vendor at all — a restaurant slip, a payment stub —
        // must be able to say so, because an invented merchant is worse than none.
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 >= Self.minimumMerchantScore
        else { return nil }

        return best.0
    }

    /// The shop's name where the only place it is printed is the closing sign-off.
    ///
    /// Anchored to the sign-off rather than scanning the footer freely, because the footer is
    /// where the payment networks, the terminal IDs and the survey URLs live and several of
    /// them read as convincingly like a name as the vendor does. A greeting that trails off on
    /// "AT" or "CHEZ" is a sentence with its object on the next line, and that next line is
    /// the only thing here worth trusting.
    private func signOffMerchant(in lines: [String]) -> String? {
        let footer = Array(lines.suffix(Self.footerDepth))
        guard let signOff = footer.firstIndex(where: Self.introducesAName) else { return nil }

        return footer[footer.index(after: signOff)...]
            .lazy
            .compactMap(merchantCandidate)
            .first { $0.score >= Self.minimumMerchantScore }?
            .name
    }

    /// Whether a line is a sign-off whose sentence finishes on the line below it.
    private static func introducesAName(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        guard greetings.contains(where: lowercased.contains) else { return false }
        guard let closingWord = lowercased.split(whereSeparator: \.isWhitespace).last else {
            return false
        }
        return nameIntroducers.contains(
            closingWord.trimmingCharacters(in: .punctuationCharacters)
        )
    }

    /// Everything a line has to survive to be a vendor name at all, and what it is worth
    /// before position is taken into account. Position is the one signal that differs between
    /// reading down from the letterhead and reading up from the sign-off.
    private func merchantCandidate(_ line: String) -> (name: String, score: Int)? {
        let cleanedLine = cleanedMerchantLine(line)
        guard cleanedLine.rangeOfCharacter(from: .letters) != nil else { return nil }

        let lowercased = cleanedLine.lowercased()
        guard Self.blockedTokens.contains(where: lowercased.contains) == false else {
            return nil
        }

        // A vendor name never has a price in it.
        guard cleanedLine.range(of: #"\d[.,]\d{2}"#, options: .regularExpression) == nil
        else { return nil }

        // Nor does it open with a number. A leading count is an item line
        // ("2 10 oz Prime Rib"), and a leading street number is the address line
        // directly under the name — neither is the vendor.
        guard cleanedLine.range(of: #"^\d"#, options: .regularExpression) == nil
        else { return nil }

        let lettersOnly = cleanedLine.filter(\.isLetter).count
        let digitsOnly = cleanedLine.filter(\.isNumber).count
        guard lettersOnly >= 3, digitsOnly <= max(3, lettersOnly / 2) else { return nil }

        var score = 0
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

    /// Genuine letterhead lines score around 20 and up: near the top of the receipt, often
    /// upper-case, short enough to be a name.
    private static let minimumMerchantScore = 10

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
        "receipt", "visa", "mastercard", "debit", "interac", "amount", "date", "time",
        // "approv" rather than "approval": the terminal prints "APPROVED" just as often, and
        // upper-case and alone on its line it scores like a name.
        "terminal", "approv", "transaction", "merchant id", "auth",
        "welcome", "thank you", "merci", "bienvenue",
        // Both halves of the pair. Only the customer's was listed, and a slip whose first
        // line reads "MERCHANT COPY" handed that back as the vendor: upper-case, short and
        // first, which is 32 points against a threshold of 10.
        "customer copy", "merchant copy",
        "hours", "www.", "http", "tel:", "phone"
    ]

    /// Words that mark a line as a greeting rather than a name. Kept separate from
    /// `blockedTokens`, which the greeting is also in — one rejects the line, this one asks
    /// whether the line is pointing at the one below it.
    private static let greetings = ["thank", "merci", "welcome", "bienvenue"]

    /// Words a sign-off breaks on when its object — the shop's name — is printed on the next
    /// line: "THANK YOU FOR SHOPPING AT", "MERCI D'AVOIR MAGASINÉ CHEZ". A greeting that ends
    /// on anything else is just a greeting, and what follows it is a timestamp or a survey URL.
    private static let nameIntroducers: Set<String> = ["at", "chez", "from", "with"]

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
