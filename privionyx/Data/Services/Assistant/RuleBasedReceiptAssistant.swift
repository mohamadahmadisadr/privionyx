import Foundation

/// Deterministic, fully offline assistant. It never leaves the device, needs no model
/// download, and is always available — so it is the default engine and the fallback
/// whenever another backend reports itself unavailable.
struct RuleBasedReceiptAssistant: ReceiptAssistant {
    func availability() async -> AssistantAvailability { .available }

    func suggestedPrompts(for context: AssistantContext) -> [String] {
        var prompts: [String] = []

        if let leading = topCategory(in: context.currentMonthReceipts) {
            prompts.append("How much on \(leading.lowercased()) this month?")
        }
        prompts.append("Find duplicate charges")
        if context.mostRecentReceipt != nil {
            prompts.append("Summarize my last receipt")
        }
        prompts.append("What did I spend this month?")

        return Array(prompts.prefix(4))
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        let query = prompt.lowercased()

        guard context.receipts.isEmpty == false else {
            return "I don't have any receipts to work with yet. Scan one from the Camera tab and I can break down totals, categories, and merchants for you."
        }

        if query.contains("duplicate") || query.contains("double charge") || query.contains("charged twice") {
            return duplicateAnswer(context: context)
        }

        if query.contains("last receipt") || query.contains("latest") || query.contains("most recent") || query.contains("categorize") {
            return lastReceiptAnswer(context: context)
        }

        if query.contains("tax") {
            return taxAnswer(context: context)
        }

        if let category = matchedCategory(in: query, context: context) {
            return categoryAnswer(category: category, context: context)
        }

        if query.contains("top") || query.contains("most") || query.contains("merchant") || query.contains("vendor") || query.contains("where") {
            return topMerchantAnswer(context: context)
        }

        if query.contains("spend") || query.contains("spent") || query.contains("total") || query.contains("how much") {
            return totalAnswer(context: context)
        }

        return fallbackAnswer(context: context)
    }

    // MARK: - Answers

    private func totalAnswer(context: AssistantContext) -> String {
        let monthly = context.currentMonthReceipts
        guard monthly.isEmpty == false else {
            let total = context.receipts.reduce(0) { $0 + $1.amount }
            return "Nothing recorded this month yet. Across all \(context.receipts.count) saved receipts you've spent \(money(total))."
        }

        let total = monthly.reduce(0) { $0 + $1.amount }
        var answer = "You've spent \(money(total)) this month across \(receiptCount(monthly.count))."

        if let leading = topCategory(in: monthly) {
            let categoryTotal = monthly.filter { $0.category == leading }.reduce(0) { $0 + $1.amount }
            answer += " \(leading) leads at \(money(categoryTotal))."
        }
        return answer
    }

    private func categoryAnswer(category: String, context: AssistantContext) -> String {
        let monthly = context.currentMonthReceipts.filter { $0.category == category }
        guard monthly.isEmpty == false else {
            return "No \(category) spending recorded this month."
        }

        let total = monthly.reduce(0) { $0 + $1.amount }
        var answer = "You've spent \(money(total)) on \(category) across \(receiptCount(monthly.count)) this month."

        let previous = previousMonthReceipts(context: context).filter { $0.category == category }
        if previous.isEmpty == false {
            let previousTotal = previous.reduce(0) { $0 + $1.amount }
            if previousTotal > 0 {
                let delta = ((total - previousTotal) / previousTotal) * 100
                answer += " That's \(abs(Int(delta.rounded())))% \(delta >= 0 ? "up from" : "down from") last month."
            }
        }

        if let top = topMerchant(in: monthly) {
            answer += " Top merchant: \(top.name) (\(money(top.amount)))."
        }
        return answer
    }

    private func topMerchantAnswer(context: AssistantContext) -> String {
        let monthly = context.currentMonthReceipts.isEmpty ? context.receipts : context.currentMonthReceipts
        guard let top = topMerchant(in: monthly) else {
            return "I couldn't find enough data to rank merchants yet."
        }
        let scope = context.currentMonthReceipts.isEmpty ? "overall" : "this month"
        return "\(top.name) is your biggest merchant \(scope) at \(money(top.amount)) across \(receiptCount(top.count))."
    }

    private func taxAnswer(context: AssistantContext) -> String {
        let monthly = context.currentMonthReceipts
        let taxed = monthly.compactMap(\.tax)
        guard taxed.isEmpty == false else {
            return "None of this month's receipts have a tax amount recorded yet."
        }
        let total = taxed.reduce(0, +)
        return "You've paid \(money(total)) in tax this month, recorded on \(taxed.count) of \(monthly.count) receipts."
    }

    private func lastReceiptAnswer(context: AssistantContext) -> String {
        guard let receipt = context.mostRecentReceipt else {
            return "No receipts saved yet."
        }
        var answer = "\(receipt.merchant) · \(money(receipt.amount)) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)), categorized as \(receipt.category)."
        if let tax = receipt.tax, tax > 0 {
            answer += " Tax was \(money(tax))."
        }
        return answer
    }

    private func duplicateAnswer(context: AssistantContext) -> String {
        let duplicates = findDuplicates(in: context.receipts)
        guard duplicates.isEmpty == false else {
            return "Checked all \(context.receipts.count) receipts — no duplicate charges found. Everything looks clean."
        }

        let lines = duplicates.prefix(3).map { pair in
            "• \(pair.merchant) \(money(pair.amount)) on \(pair.first.formatted(date: .abbreviated, time: .omitted)) and \(pair.second.formatted(date: .abbreviated, time: .omitted))"
        }
        let heading = duplicates.count == 1 ? "1 possible duplicate" : "\(duplicates.count) possible duplicates"
        return "Found \(heading):\n" + lines.joined(separator: "\n")
    }

    private func fallbackAnswer(context: AssistantContext) -> String {
        let total = context.currentMonthReceipts.reduce(0) { $0 + $1.amount }
        return "I can break spending down by category, rank merchants, total your tax, flag duplicate charges, or summarize your latest receipt. So far this month you're at \(money(total))."
    }

    // MARK: - Analysis helpers

    private func matchedCategory(in query: String, context: AssistantContext) -> String? {
        let categories = Set(context.receipts.map(\.category))

        // Direct name match first, so custom category names work without a synonym list.
        if let direct = categories.first(where: { query.contains($0.lowercased()) }) {
            return direct
        }

        let synonyms: [String: [String]] = [
            "Dining": ["food", "eat", "restaurant", "coffee", "lunch", "dinner"],
            "Grocery": ["groceries", "supermarket"],
            "Travel": ["flight", "hotel", "trip"],
            "Gas": ["fuel", "petrol"],
            "Shopping": ["shop", "retail", "clothes"],
            "Utilities": ["bill", "electric", "internet"]
        ]

        for (category, words) in synonyms where categories.contains(category) {
            if words.contains(where: { query.contains($0) }) { return category }
        }
        return nil
    }

    private func topCategory(in receipts: [AssistantReceipt]) -> String? {
        Dictionary(grouping: receipts, by: \.category)
            .max { $0.value.reduce(0) { $0 + $1.amount } < $1.value.reduce(0) { $0 + $1.amount } }?
            .key
    }

    private func topMerchant(in receipts: [AssistantReceipt]) -> (name: String, amount: Double, count: Int)? {
        Dictionary(grouping: receipts, by: \.merchant)
            .map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .max { $0.amount < $1.amount }
    }

    private func previousMonthReceipts(context: AssistantContext) -> [AssistantReceipt] {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: context.referenceDate) else { return [] }
        return context.receipts.filter { calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month) }
    }

    /// Same merchant and amount within three days of each other.
    private func findDuplicates(in receipts: [AssistantReceipt]) -> [(merchant: String, amount: Double, first: Date, second: Date)] {
        var results: [(merchant: String, amount: Double, first: Date, second: Date)] = []

        for group in Dictionary(grouping: receipts, by: \.merchant).values {
            let sorted = group.sorted { $0.date < $1.date }
            for (index, receipt) in sorted.enumerated() {
                for other in sorted.dropFirst(index + 1) {
                    guard abs(receipt.amount - other.amount) < 0.01 else { continue }
                    let daysApart = abs(other.date.timeIntervalSince(receipt.date)) / 86_400
                    guard daysApart <= 3 else { continue }
                    results.append((receipt.merchant, receipt.amount, receipt.date, other.date))
                }
            }
        }
        return results
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }

    private func receiptCount(_ count: Int) -> String {
        count == 1 ? "1 receipt" : "\(count) receipts"
    }
}
