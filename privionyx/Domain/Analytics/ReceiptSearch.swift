import Foundation

/// Works out which of the user's receipts a chat message is asking to see.
///
/// Deliberately deterministic and engine-independent. The cards under a reply have to be
/// real receipts whichever backend answered, and a small on-device model asked to emit
/// identifiers will sooner or later emit one that doesn't exist — so the engine writes the
/// prose and this decides what the prose is pointing at. It reads the same fields
/// `ExpenseAnalytics` reasons over, and reuses its merchant, category, and period matching
/// so "Whole Foods in June" means the same thing to the search as it does to the answer.
struct ReceiptSearch {
    /// How many cards a reply carries. Past this the transcript turns into a receipt list,
    /// which is what the Receipts screen is for — the caption says how many were left out.
    static let displayLimit = 6

    struct Result: Equatable {
        /// Newest first, capped at `displayLimit`, so the cards read like the receipt list.
        let receipts: [AssistantReceipt]
        /// How many matched in total, including any beyond the cap.
        let totalCount: Int
        /// What the search understood, phrased for a caption: "Starbucks · this month".
        let label: String

        var isTruncated: Bool { totalCount > receipts.count }
    }

    private let analytics: ExpenseAnalytics

    init(context: AssistantContext, calendar: Calendar = .current) {
        analytics = ExpenseAnalytics(context: context, calendar: calendar)
    }

    init(analytics: ExpenseAnalytics) {
        self.analytics = analytics
    }

    /// The receipts `query` is asking to see, or `nil` when it isn't asking for any.
    ///
    /// Returning `nil` rather than an empty result matters: "how much did I spend on dining?"
    /// is a question about a number, and hanging a stack of cards under the answer to every
    /// such question would bury the answer.
    func results(for query: String) -> Result? {
        guard analytics.isEmpty == false else { return nil }

        let q = query.lowercased()
        let filters = Filters(query: q, analytics: analytics)

        if let single = singleReceiptResult(query: q, filters: filters) {
            return single
        }

        guard isLookup(q, filters: filters) else { return nil }

        let matches = filters.apply(to: analytics.receipts).sorted { $0.date > $1.date }
        guard matches.isEmpty == false else { return nil }

        return Result(
            receipts: Array(matches.prefix(Self.displayLimit)),
            totalCount: matches.count,
            label: filters.label(fallback: "Recent receipts")
        )
    }

    // MARK: - Intent

    /// Phrases that ask to *see* receipts rather than to know a figure about them.
    private static let lookupCues = [
        "find", "search", "look up", "lookup", "pull up", "show me", "show my", "show the",
        "list ", "which receipt", "what receipt", "any receipt", "do i have", "open ", "see my"
    ]

    private func isLookup(_ query: String, filters: Filters) -> Bool {
        if Self.lookupCues.contains(where: { query.contains($0) }) { return true }
        // "starbucks receipts", "receipts over $50" — a noun phrase with no verb is still
        // unambiguously a request to see them, as long as it narrows to something.
        return query.contains("receipt") && filters.isNarrowed
    }

    /// Questions that name one particular receipt. Answering "your biggest purchase was
    /// £312 at Dyson" and leaving the user to go find it by hand is the gap this closes.
    private func singleReceiptResult(query: String, filters: Filters) -> Result? {
        // "biggest category" and "top merchant" rank groups, not receipts — there is no one
        // receipt to open, so leave those to the prose.
        guard containsAny(query, ["category", "categories", "merchant", "vendor", "store"]) == false else {
            return nil
        }

        // Free text is ignored here: these are whole sentences, and their leftover words
        // ("biggest", "purchase") describe the question, not a merchant to filter on.
        let scoped = filters.apply(to: analytics.receipts, matchingFreeText: false)
        guard scoped.isEmpty == false else { return nil }

        let receipt: AssistantReceipt?
        let subject: String

        if containsAny(query, ["biggest", "largest", "most expensive", "priciest", "highest", "single largest"]) {
            receipt = scoped.max { $0.amount < $1.amount }
            subject = "Largest purchase"
        } else if containsAny(query, ["smallest", "cheapest", "least expensive", "lowest"]) {
            receipt = scoped.min { $0.amount < $1.amount }
            subject = "Smallest purchase"
        } else if containsAny(query, ["last receipt", "latest receipt", "most recent", "last purchase", "latest purchase", "last thing i", "just bought", "just spent"]) {
            receipt = scoped.max { $0.date < $1.date }
            subject = "Most recent"
        } else {
            return nil
        }

        guard let receipt else { return nil }
        return Result(receipts: [receipt], totalCount: 1, label: filters.label(fallback: subject, prefix: subject))
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    // MARK: - Filters

    /// The constraints read out of a question: who, what, when, how much.
    private struct Filters {
        let merchant: String?
        let category: String?
        let range: ExpenseAnalytics.DateRange?
        let minimumAmount: Double?
        let maximumAmount: Double?
        /// Words left over after the known merchants and the query's own vocabulary are
        /// accounted for — matched loosely so "amaz" finds Amazon.
        let freeText: [String]

        init(query: String, analytics: ExpenseAnalytics) {
            let merchant = analytics.matchMerchant(in: query)
            self.merchant = merchant
            category = analytics.matchCategory(in: query)
            range = analytics.detectRange(in: query)

            let bounds = Self.amountBounds(in: query)
            minimumAmount = bounds.minimum
            maximumAmount = bounds.maximum

            // A last resort, and only when nothing precise was recognised. "Coffee receipts"
            // already resolves to the Dining category, and also demanding that the word
            // "coffee" appear on the receipt would throw away every match it just found.
            let recognisedSomething = merchant != nil || category != nil || range != nil
                || bounds.minimum != nil || bounds.maximum != nil
            freeText = recognisedSomething ? [] : Self.candidateWords(in: query)
        }

        var isNarrowed: Bool {
            merchant != nil || category != nil || range != nil
                || minimumAmount != nil || maximumAmount != nil || freeText.isEmpty == false
        }

        func apply(to receipts: [AssistantReceipt], matchingFreeText: Bool = true) -> [AssistantReceipt] {
            let words = matchingFreeText ? freeText : []

            return receipts.filter { receipt in
                if let merchant, receipt.merchant != merchant { return false }
                if let category, receipt.category != category { return false }
                if let range, range.contains(receipt.date) == false { return false }
                if let minimumAmount, receipt.amount < minimumAmount { return false }
                if let maximumAmount, receipt.amount > maximumAmount { return false }
                if words.isEmpty == false, Self.matchesLoosely(receipt, words: words) == false { return false }
                return true
            }
        }

        func label(fallback: String, prefix: String? = nil) -> String {
            var parts: [String] = []
            if let prefix { parts.append(prefix) }
            if let merchant { parts.append(merchant) }
            if let category, merchant == nil { parts.append(category) }
            if let range, range.isAllTime == false { parts.append(range.label) }
            if let minimumAmount { parts.append("over \(PrivionyxCurrencyFormatter.string(for: minimumAmount))") }
            if let maximumAmount { parts.append("under \(PrivionyxCurrencyFormatter.string(for: maximumAmount))") }

            return parts.isEmpty ? fallback : parts.joined(separator: " · ")
        }

        // MARK: Amounts

        private static let lowerBoundCues = ["over ", "above ", "more than ", "greater than ", "at least ", "bigger than ", "larger than "]
        private static let upperBoundCues = ["under ", "below ", "less than ", "cheaper than ", "at most ", "no more than "]

        private static func amountBounds(in query: String) -> (minimum: Double?, maximum: Double?) {
            (amount(in: query, after: lowerBoundCues), amount(in: query, after: upperBoundCues))
        }

        /// The first figure following any of `cues` — "over $50", "more than 20.50".
        private static func amount(in query: String, after cues: [String]) -> Double? {
            for cue in cues {
                guard let cueRange = query.range(of: cue) else { continue }
                let remainder = query[cueRange.upperBound...]

                let digits = remainder
                    .drop { $0.isNumber == false && $0 != "." }
                    .prefix { $0.isNumber || $0 == "." }

                if let value = Double(digits), value > 0 { return value }
            }
            return nil
        }

        // MARK: Free text

        /// Query scaffolding — verbs, prepositions, and period words that describe the
        /// question rather than the receipt, so they must never be matched against a merchant.
        private static let stopWords: Set<String> = [
            "find", "search", "show", "list", "open", "see", "look", "up", "pull", "get",
            "receipt", "receipts", "purchase", "purchases", "bought", "buy", "spent", "spend",
            "me", "my", "mine", "the", "a", "an", "all", "any", "some", "that", "this", "those",
            "from", "for", "at", "in", "on", "of", "to", "with", "and", "or", "by",
            "do", "did", "does", "have", "has", "had", "was", "were", "is", "are", "am",
            "i", "you", "it", "what", "which", "when", "where", "who", "how", "much", "many",
            "last", "latest", "recent", "most", "least", "over", "under", "than", "more", "less",
            "about", "again", "please", "can", "could", "would", "want", "need", "give",
            "day", "days", "week", "weeks", "month", "months", "year", "years", "today", "yesterday"
        ]

        private static func candidateWords(in query: String) -> [String] {
            query
                .split { $0.isLetter == false && $0.isNumber == false }
                .map(String.init)
                .filter { $0.count >= 3 && stopWords.contains($0) == false && Int($0) == nil }
        }

        /// A receipt matches loose text when any word overlaps its merchant or category in
        /// either direction, so both a truncation ("amaz") and an elaboration ("starbucks
        /// coffee") land on the same receipt.
        private static func matchesLoosely(_ receipt: AssistantReceipt, words: [String]) -> Bool {
            let haystacks = [receipt.merchant.lowercased(), receipt.category.lowercased()]

            return words.contains { word in
                haystacks.contains { haystack in
                    haystack.contains(word) || (word.count >= 4 && word.contains(haystack))
                }
            }
        }
    }
}
