import Foundation

/// Deterministic, fully offline assistant. It never leaves the device, needs no model
/// download, and is always available — so it is the default engine and the fallback
/// whenever another backend reports itself unavailable.
///
/// Every figure it quotes comes from `ExpenseAnalytics`, so the arithmetic is computed and
/// tested in one place. This engine's job is to recognise what a question is asking and
/// phrase the numbers back conversationally.
struct RuleBasedReceiptAssistant: ReceiptAssistant {
    func availability() async -> AssistantAvailability { .available }

    func suggestedPrompts(for context: AssistantContext) -> [String] {
        let analytics = ExpenseAnalytics(context: context)
        var prompts: [String] = []

        if let leading = analytics.byCategory(analytics.receipts(in: analytics.currentMonth)).first {
            prompts.append("How much on \(leading.name.lowercased()) this month?")
        }
        if let topMerchant = analytics.byMerchant(context.receipts).first {
            prompts.append("How much at \(topMerchant.name)?")
        }
        prompts.append("What was my biggest purchase?")
        prompts.append("Compare this month to last month")
        prompts.append("Any unusual spending?")

        return Array(prompts.prefix(4))
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        let query = prompt.lowercased()
        let analytics = ExpenseAnalytics(context: context)

        guard analytics.isEmpty == false else {
            return "I don't have any receipts to work with yet. Scan one from the Camera tab and I can break down totals, categories, merchants, and trends for you."
        }

        if matches(query, ["what can you", "what do you do", "help me with", "how do you work", "capabilities"]) {
            return capabilitiesAnswer()
        }
        if matches(query, ["duplicate", "double charge", "charged twice", "charged me twice"]) {
            return duplicateAnswer(analytics)
        }
        if matches(query, ["unusual", "anomal", "outlier", "stand out", "standout", "suspicious", "strange", "weird", "odd charge"]) {
            return anomalyAnswer(analytics)
        }
        if matches(query, ["last receipt", "latest", "most recent", "recent receipt", "last purchase", "last time", "last one", "last thing", "just bought", "just spent", "just spend"]) {
            return lastReceiptAnswer(analytics)
        }
        if matches(query, ["tax"]) {
            return taxAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["average", "typical", "mean ", "per receipt", "on average"]) {
            return averageAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["how many receipt", "how many purchase", "number of receipt", "receipt count"]) {
            return countAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["biggest", "largest", "most expensive", "priciest", "highest", "single largest"]) {
            return extremeAnswer(query: query, analytics: analytics, largest: true)
        }
        if matches(query, ["smallest", "cheapest", "least expensive", "lowest"]) {
            return extremeAnswer(query: query, analytics: analytics, largest: false)
        }
        if matches(query, ["compare", "versus", " vs ", "vs.", "trend", "more than last", "less than last", "than last month"]) {
            return trendAnswer(query: query, analytics: analytics)
        }
        // A named merchant is a strong signal — check it before generic "top merchant".
        if let merchant = analytics.matchMerchant(in: query), mentionsMerchantIntent(query) {
            return merchantAnswer(merchant: merchant, query: query, analytics: analytics)
        }
        if let category = analytics.matchCategory(in: query) {
            return categoryAnswer(category: category, query: query, analytics: analytics)
        }
        if matches(query, ["breakdown", "break down", "categories", "where is my money", "where does my money", "where's my money"]) {
            return breakdownAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["top merchant", "biggest merchant", "top vendor", "merchant", "vendor", "who do i", "where do i shop"]) {
            return topMerchantAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["spend", "spent", "total", "how much", "cost me"]) {
            return totalAnswer(query: query, analytics: analytics)
        }

        return overviewAnswer(analytics)
    }

    // MARK: - Answers

    private func totalAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let agg = analytics.aggregate(receipts)

        guard agg.count > 0 else {
            return "Nothing recorded \(range.label). \(allTimeReminder(analytics))"
        }

        var answer = "You spent \(money(agg.total)) \(range.label) across \(receiptCount(agg.count))"
        if let leading = analytics.byCategory(receipts).first, leading.total > 0 {
            answer += ", led by \(leading.name) at \(money(leading.total))."
        } else {
            answer += "."
        }
        return answer
    }

    private func categoryAnswer(category: String, query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.allTime)
        let inCategory = receipts.filter { $0.category == category }
        let agg = analytics.aggregate(inCategory)

        guard agg.count > 0 else {
            return "No \(category) spending recorded \(range.label)."
        }

        var answer = "You spent \(money(agg.total)) on \(category) \(range.label) across \(receiptCount(agg.count))"

        if let top = analytics.byMerchant(inCategory).first {
            answer += ", mostly at \(top.name) (\(money(top.total)))."
        } else {
            answer += "."
        }

        // Offer a month-over-month read when the question is scoped to the current month.
        if range == analytics.currentMonth {
            let trend = analytics.monthOverMonth(category: category)
            if let delta = trend.deltaPercent {
                answer += " That's \(abs(Int(delta.rounded())))% \(trend.isUp ? "up from" : "down from") last month."
            }
        }
        return answer
    }

    private func merchantAnswer(merchant: String, query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.allTime)
        let atMerchant = receipts.filter { $0.merchant == merchant }
        let agg = analytics.aggregate(atMerchant)

        guard agg.count > 0 else {
            return "No spending at \(merchant) \(range.label)."
        }

        let scopeLabel = range.isAllTime ? "" : " \(range.label)"
        var answer = "You've spent \(money(agg.total)) at \(merchant)\(scopeLabel) across \(receiptCount(agg.count))"
        if agg.count > 1 {
            answer += ", averaging \(money(agg.average)) a visit."
        } else {
            answer += "."
        }
        return answer
    }

    private func topMerchantAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let merchants = analytics.byMerchant(receipts)

        guard let top = merchants.first else {
            // Nothing in the scoped range — fall back to all time so the user still gets an answer.
            guard let overall = analytics.byMerchant(analytics.receipts).first else {
                return "I couldn't find enough data to rank merchants yet."
            }
            return "\(overall.name) is your biggest merchant overall at \(money(overall.total)) across \(receiptCount(overall.count))."
        }

        var answer = "\(top.name) is your biggest merchant \(range.label) at \(money(top.total)) across \(receiptCount(top.count))."
        if merchants.count > 1 {
            answer += " Then \(merchants[1].name) at \(money(merchants[1].total))."
        }
        return answer
    }

    private func breakdownAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let categories = analytics.byCategory(receipts)

        guard categories.isEmpty == false else {
            return "Nothing recorded \(range.label) to break down. \(allTimeReminder(analytics))"
        }

        let total = analytics.aggregate(receipts).total
        let lines = categories.prefix(4).map { group -> String in
            let share = total > 0 ? Int((group.total / total * 100).rounded()) : 0
            return "• \(group.name): \(money(group.total)) (\(share)%)"
        }
        return "Here's where your money went \(range.label) (\(money(total)) total):\n" + lines.joined(separator: "\n")
    }

    private func averageAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        // "average on <category>" narrows to a category; otherwise it's per-receipt overall.
        if let category = analytics.matchCategory(in: query) {
            let receipts = scope(query, analytics, default: analytics.allTime).receipts.filter { $0.category == category }
            let agg = analytics.aggregate(receipts)
            guard agg.count > 0 else { return "No \(category) spending to average yet." }
            return "Your average \(category) receipt is \(money(agg.average)), across \(receiptCount(agg.count))."
        }

        let (receipts, range) = scope(query, analytics, default: analytics.allTime)
        let agg = analytics.aggregate(receipts)
        guard agg.count > 0 else { return "Nothing recorded \(range.label) to average." }
        let scopeLabel = range.isAllTime ? "" : " \(range.label)"
        return "Your average receipt\(scopeLabel) is \(money(agg.average)), from \(receiptCount(agg.count)) totalling \(money(agg.total))."
    }

    private func countAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.allTime)
        let agg = analytics.aggregate(receipts)
        let scopeLabel = range.isAllTime ? "in total" : range.label
        return "You have \(receiptCount(agg.count)) \(scopeLabel), worth \(money(agg.total))."
    }

    private func extremeAnswer(query: String, analytics: ExpenseAnalytics, largest: Bool) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.allTime)

        // "biggest category" / "biggest merchant" ask about a group, not a single receipt.
        if matches(query, ["category", "categories"]), let top = analytics.byCategory(receipts).first {
            return "\(top.name) is your \(largest ? "biggest" : "smallest") category \(range.isAllTime ? "overall" : range.label) at \(money(top.total))."
        }
        if matches(query, ["merchant", "vendor", "store"]) {
            return topMerchantAnswer(query: query, analytics: analytics)
        }

        guard let receipt = largest ? analytics.largestPurchase(in: receipts) : analytics.smallestPurchase(in: receipts) else {
            return "Nothing recorded \(range.label) to compare."
        }
        let scopeLabel = range.isAllTime ? "" : " \(range.label)"
        return "Your \(largest ? "biggest" : "smallest") single purchase\(scopeLabel) was \(money(receipt.amount)) at \(receipt.merchant) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)) (\(receipt.category))."
    }

    private func trendAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let category = analytics.matchCategory(in: query)
        let trend = analytics.monthOverMonth(category: category)
        let subject = category.map { "\($0) spending" } ?? "Spending"

        guard trend.current > 0 || trend.previous > 0 else {
            return "Not enough history yet to compare this month with last."
        }

        var answer = "\(subject) is \(money(trend.current)) this month vs. \(money(trend.previous)) last month"
        if let delta = trend.deltaPercent {
            answer += " — \(abs(Int(delta.rounded())))% \(trend.isUp ? "higher" : "lower")."
        } else if trend.current > 0 {
            answer += " — all of it new this month."
        } else {
            answer += "."
        }
        return answer
    }

    private func taxAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let tax = analytics.tax(in: receipts)
        guard tax.taxedCount > 0 else {
            return "None of \(range.isAllTime ? "your" : "\(range.label)'s") receipts have a tax amount recorded yet."
        }
        return "You paid \(money(tax.total)) in tax \(range.label), recorded on \(tax.taxedCount) of \(receiptCount(receipts.count))."
    }

    private func lastReceiptAnswer(_ analytics: ExpenseAnalytics) -> String {
        guard let receipt = analytics.mostRecent else {
            return "No receipts saved yet."
        }
        var answer = "\(receipt.merchant) · \(money(receipt.amount)) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)), categorized as \(receipt.category)."
        if let tax = receipt.tax, tax > 0 {
            answer += " Tax was \(money(tax))."
        }
        return answer
    }

    private func duplicateAnswer(_ analytics: ExpenseAnalytics) -> String {
        let duplicates = analytics.duplicates()
        guard duplicates.isEmpty == false else {
            return "Checked all \(receiptCount(analytics.receipts.count)) — no duplicate charges found. Everything looks clean."
        }

        let lines = duplicates.prefix(3).map { pair in
            "• \(pair.merchant) \(money(pair.amount)) on \(pair.first.formatted(date: .abbreviated, time: .omitted)) and \(pair.second.formatted(date: .abbreviated, time: .omitted))"
        }
        let heading = duplicates.count == 1 ? "1 possible duplicate" : "\(duplicates.count) possible duplicates"
        return "Found \(heading):\n" + lines.joined(separator: "\n")
    }

    private func anomalyAnswer(_ analytics: ExpenseAnalytics) -> String {
        let anomalies = analytics.anomalies()
        guard anomalies.isEmpty == false else {
            return "Nothing stands out — your spending is consistent with your usual patterns across every category."
        }

        let lines = anomalies.prefix(3).map { anomaly -> String in
            let receipt = anomaly.receipt
            let times = String(format: "%.1f", anomaly.timesTypical)
            return "• \(receipt.merchant) \(money(receipt.amount)) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)) — \(times)× your usual \(receipt.category.lowercased())"
        }
        let heading = anomalies.count == 1 ? "1 purchase stands out" : "\(anomalies.count) purchases stand out"
        return "\(heading):\n" + lines.joined(separator: "\n")
    }

    private func overviewAnswer(_ analytics: ExpenseAnalytics) -> String {
        let month = analytics.aggregate(in: analytics.currentMonth)
        let all = analytics.aggregate(analytics.receipts)

        var answer = "I can break spending down by category, add up any merchant or time range, spot your biggest purchases, compare months, total your tax, or flag duplicates and unusual charges — just ask."
        if month.count > 0 {
            answer += " So far this month you're at \(money(month.total)) across \(receiptCount(month.count))."
        } else if all.count > 0 {
            answer += " You've logged \(receiptCount(all.count)) totalling \(money(all.total))."
        }
        return answer
    }

    private func capabilitiesAnswer() -> String {
        "Ask me anything about your receipts: totals for any month, year, or merchant; category breakdowns; your biggest or average purchase; how this month compares to last; tax paid; or duplicate and unusual charges. Try “how much at Amazon this year?” or “compare dining to last month.”"
    }

    // MARK: - Helpers

    /// Resolves the receipts a question is scoped to: the period it names, or `default` when
    /// it names none. Returns both the filtered receipts and the range so answers can label it.
    private func scope(
        _ query: String,
        _ analytics: ExpenseAnalytics,
        default fallback: ExpenseAnalytics.DateRange
    ) -> (receipts: [AssistantReceipt], range: ExpenseAnalytics.DateRange) {
        let range = analytics.detectRange(in: query) ?? fallback
        return (analytics.receipts(in: range), range)
    }

    private func allTimeReminder(_ analytics: ExpenseAnalytics) -> String {
        let all = analytics.aggregate(analytics.receipts)
        return "Across all \(receiptCount(all.count)) you've spent \(money(all.total))."
    }

    private func mentionsMerchantIntent(_ query: String) -> Bool {
        // Guard against a merchant name that's also a common word swallowing unrelated
        // questions: only treat it as a merchant query when the phrasing fits one.
        matches(query, ["at ", "from ", "how much", "spend", "spent", "total", "pay", "paid", "cost"])
    }

    private func matches(_ query: String, _ needles: [String]) -> Bool {
        needles.contains { query.contains($0) }
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }

    private func receiptCount(_ count: Int) -> String {
        count == 1 ? "1 receipt" : "\(count) receipts"
    }
}
