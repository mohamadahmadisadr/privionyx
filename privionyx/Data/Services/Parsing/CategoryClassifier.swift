import Foundation

nonisolated struct CategoryClassifier {
    /// Keyword scoring covers the merchant plus the letterhead only. Scoring the whole
    /// receipt let item names decide the category — a restaurant that served "SPARKLING
    /// WATER" classified as Utilities off the word "water".
    private static let headerDepth = 6

    func categorize(merchant: String, lines: [String]) -> ReceiptCategory {
        // Asked before the merchant is, and only for fuel. A dispenser prints what it sold —
        // pump number, grade, litres, price per litre — and that describes the transaction,
        // where the merchant only describes the business. The two disagree at every warehouse
        // club and hardware chain that runs a gas bar: a Costco fill-up scored as Shopping on
        // the word "costco" while four separate fuel markers sat further down the receipt.
        // Dining is deliberately not promoted this way — a rideshare receipt has a tip line
        // and is still travel — so the fallback below keeps handling it.
        if fuelStructureIsUnmistakable(in: lines) {
            return .gas
        }

        let scope = ([merchant] + lines.prefix(Self.headerDepth))
            .joined(separator: " ")
            .lowercased()

        let best = Self.categoryKeywords
            .map { entry in
                let score = entry.keywords.reduce(into: 0) { partialResult, keyword in
                    guard MerchantExtractor.containsWord(keyword, in: scope) else { return }
                    partialResult += keyword.contains(" ") ? 4 : 2
                }
                return (category: entry.category, score: score)
            }
            .max { $0.score < $1.score }

        if let best, best.score > 0 {
            return best.category
        }

        // Only consulted when the merchant itself says nothing. Structural markers must not
        // outrank a named merchant: a rideshare receipt has a tip line but is travel, not dining.
        return structuralCategory(in: lines) ?? .shopping
    }

    /// Whether the receipt is unambiguously a fuel sale.
    ///
    /// Two distinct markers are required rather than one, because any single marker turns up
    /// innocently elsewhere: a grocery receipt sells milk by the litre, and a hardware
    /// receipt sells diesel additive. Two of them together only happen at a pump.
    private func fuelStructureIsUnmistakable(in lines: [String]) -> Bool {
        let joined = lines.joined(separator: "\n").lowercased()
        let matched = Self.fuelPatterns.filter { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
        return matched.count >= 2
    }

    /// Layout markers that identify the kind of business regardless of merchant name or
    /// item wording. A receipt with a server and a table number is a restaurant even when
    /// nothing on it matches a dining keyword — the common case for independents.
    private func structuralCategory(in lines: [String]) -> ReceiptCategory? {
        let joined = lines.joined(separator: "\n").lowercased()

        return Self.structuralSignals.first { entry in
            entry.patterns.contains { pattern in
                joined.range(of: pattern, options: .regularExpression) != nil
            }
        }?.category
    }

    /// What a fuel dispenser prints. `price/l` is matched without a trailing boundary
    /// because the label runs on into its unit — "Price/Litre:", "Price/L" — and requiring
    /// one meant the longer spelling never matched.
    private static let fuelPatterns = [
        #"\bpump\s*#"#, #"\blitres?\b"#, #"\bliters?\b"#,
        #"\bunleaded\b"#, #"\bdiesel\b"#, #"\bprice/l"#, #"\bfuel sale\b"#
    ]

    private static let structuralSignals: [(category: ReceiptCategory, patterns: [String])] = [
        (.gas, fuelPatterns),
        (.dining, [
            #"\bserver\b"#, #"\btable\s*#?\s*\d"#, #"\bguests?\s*[:#]?\s*\d"#,
            #"\bdine\s*-?\s*in\b"#, #"\bgratuity\b"#, #"\btip\b"#
        ])
    ]

    /// Ordered rather than a dictionary so ties break the same way on every run — the
    /// previous dictionary made the outcome depend on hash order. Keywords are matched at
    /// word boundaries, so "metro" no longer fires on "Metropolitan".
    private static let categoryKeywords: [(category: ReceiptCategory, keywords: [String])] = [
        (.gas, [
            "shell", "petro", "petro-canada", "esso", "fuel", "chevron", "exxon",
            "mobil", "gasoline", "essence", "station service"
        ]),
        (.grocery, [
            "whole foods", "trader joe", "aldi", "metro", "loblaws", "no frills",
            "market", "grocery", "supermarket", "kroger", "safeway", "produce",
            "marche", "supermarche", "epicerie", "fruiterie", "depanneur",
            "convenience"
        ]),
        (.health, [
            "pharmacy", "pharmacie", "drug mart", "shoppers drug", "rexall",
            "jean coutu", "clinic", "clinique", "dental", "dentist", "optical",
            "optometry", "medical", "hospital", "physio"
        ]),
        (.bills, [
            "invoice", "insurance", "premium", "policy", "assurance", "facture"
        ]),
        (.entertainment, [
            "cinema", "cineplex", "theatre", "theater", "netflix", "spotify",
            "concert", "ticketmaster"
        ]),
        (.housing, [
            "rent", "landlord", "property management", "storage", "loyer"
        ]),
        (.dining, [
            "coffee", "restaurant", "cafe", "tim hortons", "starbucks", "pizza",
            "burger", "grill", "bakery", "mcdonald", "bistro", "brasserie",
            "boulangerie", "patisserie", "traiteur"
        ]),
        (.travel, [
            "air", "airlines", "hotel", "uber", "lyft", "flight", "airport",
            "booking", "airbnb", "motel", "auberge"
        ]),
        (.utilities, [
            "power", "electric", "energy", "utility", "internet", "wireless",
            "telecom", "hydro", "hydro-quebec"
        ]),
        (.shopping, [
            "target", "walmart", "costco", "canadian tire", "store", "retail",
            "amazon", "mall", "magasin"
        ])
    ]
}
