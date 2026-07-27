import Foundation

/// Picks the prompt chips shown above the composer. Before the first question they're the
/// engine's own openers; after each answer they become follow-ups tailored to what was just
/// asked — so a question about a merchant offers to compare it, a total offers a breakdown,
/// and the conversation keeps flowing without the user having to think of the next question.
enum AssistantSuggestions {
    /// Follow-ups that make sense after the user asked `query`, grounded in their data so a
    /// suggested merchant or category actually exists. Falls back to broad openers.
    static func followUps(to query: String, context: AssistantContext) -> [String] {
        let analytics = ExpenseAnalytics(context: context)
        guard analytics.isEmpty == false else { return [] }

        let q = query.lowercased()
        var suggestions: [String] = []

        if let merchant = analytics.matchMerchant(in: q) {
            suggestions.append("Show my \(merchant) receipts")
            suggestions.append("What's my biggest purchase at \(merchant)?")
            suggestions.append("How much at \(merchant) this year?")
        }

        if let category = analytics.matchCategory(in: q) {
            suggestions.append("Compare \(category.lowercased()) to last month")
            if let topMerchant = analytics.byMerchant(analytics.receipts.filter { $0.category == category }).first {
                suggestions.append("How much at \(topMerchant.name)?")
            }
        }

        if containsAny(q, ["total", "spend", "spent", "how much"]) {
            suggestions.append("Break it down by category")
            suggestions.append("Compare this month to last month")
        }

        if containsAny(q, ["biggest", "largest", "expensive"]) {
            suggestions.append("Any unusual spending?")
        }

        // Backfill with broad, always-useful prompts so there are always a few chips.
        suggestions.append(contentsOf: defaults(analytics))

        return dedupedPrefix(suggestions, limit: 4)
    }

    private static func defaults(_ analytics: ExpenseAnalytics) -> [String] {
        var prompts = ["What did I spend this month?", "Any unusual spending?", "What was my biggest purchase?"]
        if let topCategory = analytics.byCategory(analytics.receipts).first {
            prompts.insert("How much on \(topCategory.name.lowercased())?", at: 0)
        }
        return prompts
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func dedupedPrefix(_ items: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items where seen.insert(item).inserted {
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }
}
