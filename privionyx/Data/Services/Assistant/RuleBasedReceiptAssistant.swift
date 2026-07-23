import Foundation

/// Deterministic, fully offline assistant. It never leaves the device, needs no model
/// download, and is always available — so it is the default engine and the fallback
/// whenever another backend reports itself unavailable.
///
/// Every figure it quotes comes from `ExpenseAnalytics`, so the arithmetic is computed and
/// tested in one place. This engine's job is to recognise what a question is asking and
/// phrase the numbers back conversationally. To keep it from reading like a form letter it
/// varies its wording (deterministically, seeded on the question) and, when it doesn't have
/// a dedicated handler, still answers anything that names a merchant, category, or period.
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
        prompts.append("How am I doing this month?")
        prompts.append("Where can I save?")
        prompts.append("Any unusual spending?")

        return Array(prompts.prefix(4))
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        let query = prompt.lowercased()
        let analytics = ExpenseAnalytics(context: context)

        guard analytics.isEmpty == false else {
            return "I don't have any receipts to work with yet. Scan one from the Camera tab and I can break down totals, categories, merchants, and trends for you."
        }

        // Conversational small talk first, so a plain "hi" or "thanks" doesn't get parsed
        // as a spending question — but only when the message is short enough to be just that.
        if isGreeting(query) {
            return greetingAnswer(analytics, seed: query)
        }
        if isThanks(query) {
            return variant([
                "Anytime! Ask me anything else about your spending.",
                "You got it. What else can I dig into?",
                "Happy to help — want a breakdown of anything?"
            ], seed: query)
        }

        if matches(query, ["what can you", "what do you do", "help me with", "how do you work", "capabilities"]) {
            return capabilitiesAnswer()
        }
        if matches(query, ["how am i doing", "how are my", "overview", "snapshot", "summary", "summarize my spending", "how's my spending", "how is my spending", "sum up"]) {
            return snapshotAnswer(analytics)
        }
        if matches(query, ["duplicate", "double charge", "charged twice", "charged me twice"]) {
            return duplicateAnswer(analytics)
        }
        if matches(query, ["unusual", "anomal", "outlier", "stand out", "standout", "suspicious", "strange", "weird", "odd charge"]) {
            return anomalyAnswer(analytics)
        }
        if matches(query, ["save", "cut back", "cut down", "reduce", "spend less", "spending less", "budget", "overspend", "trim"]) {
            return savingAnswer(analytics)
        }
        if matches(query, ["how often", "how many times", "number of visits", "how frequently", "how regularly"]) {
            return frequencyAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["when did", "when was", "when's the last", "when have i", "last time i"]) && matches(query, ["at ", "from ", "go to", "buy", "shop", "visit", "spend", "spent", "pay", "paid"]) {
            return whenAnswer(query: query, analytics: analytics)
        }
        if matches(query, ["list", "show me", "show my", "what are my", "which receipts", "receipts from", "receipts at"]) {
            return listAnswer(query: query, analytics: analytics)
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
        if matches(query, ["afford", "should i buy", "can i buy", "room in my budget", "on track"]) {
            return affordabilityAnswer(analytics)
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

        return fallbackAnswer(query: query, analytics: analytics)
    }

    // MARK: - Answers

    private func totalAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let agg = analytics.aggregate(receipts)

        guard agg.count > 0 else {
            return "Nothing recorded \(range.label). \(allTimeReminder(analytics))"
        }

        let lead = analytics.byCategory(receipts).first
        let tail = (lead.map { ", led by \($0.name) at \(money($0.total))" } ?? "")
        return variant([
            "You spent \(money(agg.total)) \(range.label) across \(receiptCount(agg.count))\(tail).",
            "\(range.label.capitalizedFirst) you're at \(money(agg.total)) over \(receiptCount(agg.count))\(tail).",
            "That comes to \(money(agg.total)) \(range.label), from \(receiptCount(agg.count))\(tail)."
        ], seed: query)
    }

    private func categoryAnswer(category: String, query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.allTime)
        let inCategory = receipts.filter { $0.category == category }
        let agg = analytics.aggregate(inCategory)

        guard agg.count > 0 else {
            return "No \(category) spending recorded \(range.label)."
        }

        let top = analytics.byMerchant(inCategory).first
        let where_ = top.map { ", mostly at \($0.name) (\(money($0.total)))" } ?? ""
        var answer = variant([
            "You spent \(money(agg.total)) on \(category) \(range.label) across \(receiptCount(agg.count))\(where_).",
            "\(category) came to \(money(agg.total)) \(range.label) over \(receiptCount(agg.count))\(where_).",
            "That's \(money(agg.total)) on \(category) \(range.label), from \(receiptCount(agg.count))\(where_)."
        ], seed: query)

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
        if agg.count == 1, let only = atMerchant.first {
            return "You've been to \(merchant) once\(scopeLabel): \(money(only.amount)) on \(only.date.formatted(date: .abbreviated, time: .omitted))."
        }
        return variant([
            "You've spent \(money(agg.total)) at \(merchant)\(scopeLabel) across \(receiptCount(agg.count)), averaging \(money(agg.average)) a visit.",
            "\(merchant) has cost you \(money(agg.total))\(scopeLabel) over \(receiptCount(agg.count)) — about \(money(agg.average)) each time.",
            "That's \(money(agg.total)) at \(merchant)\(scopeLabel) from \(receiptCount(agg.count)), roughly \(money(agg.average)) per visit."
        ], seed: query)
    }

    private func topMerchantAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (receipts, range) = scope(query, analytics, default: analytics.currentMonth)
        let merchants = analytics.byMerchant(receipts)

        guard let top = merchants.first else {
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
        let lines = categories.prefix(5).map { group -> String in
            let share = total > 0 ? Int((group.total / total * 100).rounded()) : 0
            return "• \(group.name): \(money(group.total)) (\(share)%)"
        }
        return "Here's where your money went \(range.label) (\(money(total)) total):\n" + lines.joined(separator: "\n")
    }

    private func averageAnswer(query: String, analytics: ExpenseAnalytics) -> String {
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
        return variant([
            "Your \(largest ? "biggest" : "smallest") single purchase\(scopeLabel) was \(money(receipt.amount)) at \(receipt.merchant) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)) (\(receipt.category)).",
            "That'd be \(money(receipt.amount)) at \(receipt.merchant)\(scopeLabel), on \(receipt.date.formatted(date: .abbreviated, time: .omitted)) under \(receipt.category)."
        ], seed: query)
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
        var answer = "Your last receipt was \(receipt.merchant) · \(money(receipt.amount)) on \(receipt.date.formatted(date: .abbreviated, time: .omitted)), categorized as \(receipt.category)."
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

    /// A conversational, multi-fact read on the month — the answer that most makes the
    /// built-in engine feel like it's actually thinking rather than filling a template.
    private func snapshotAnswer(_ analytics: ExpenseAnalytics) -> String {
        let monthReceipts = analytics.receipts(in: analytics.currentMonth)
        let month = analytics.aggregate(monthReceipts)

        guard month.count > 0 else {
            let all = analytics.aggregate(analytics.receipts)
            return "Nothing logged this month yet. All time you're at \(money(all.total)) across \(receiptCount(all.count)) — scan a receipt and I'll keep the running picture."
        }

        var parts = ["This month you're at \(money(month.total)) across \(receiptCount(month.count))."]

        let trend = analytics.monthOverMonth()
        if let delta = trend.deltaPercent {
            parts.append("That's \(abs(Int(delta.rounded())))% \(trend.isUp ? "more" : "less") than last month's \(money(trend.previous)).")
        }
        if let topCategory = analytics.byCategory(monthReceipts).first {
            parts.append("\(topCategory.name) leads at \(money(topCategory.total)).")
        }
        if let biggest = analytics.largestPurchase(in: monthReceipts) {
            parts.append("Biggest buy was \(money(biggest.amount)) at \(biggest.merchant).")
        }
        let anomalies = analytics.anomalies()
        if anomalies.isEmpty == false {
            parts.append("\(anomalies.count == 1 ? "One purchase" : "\(anomalies.count) purchases") stood out as unusually large — ask about unusual spending for details.")
        }
        return parts.joined(separator: " ")
    }

    private func savingAnswer(_ analytics: ExpenseAnalytics) -> String {
        let monthReceipts = analytics.receipts(in: analytics.currentMonth)
        let categories = analytics.byCategory(monthReceipts.isEmpty ? analytics.receipts : monthReceipts)

        guard let top = categories.first else {
            return "I don't have enough spending recorded yet to suggest where to cut back."
        }

        let scope = monthReceipts.isEmpty ? "overall" : "this month"
        var answer = "Your biggest category \(scope) is \(top.name) at \(money(top.total)) across \(receiptCount(top.count)) — the most obvious place to trim."

        let trend = analytics.monthOverMonth(category: top.name)
        if let delta = trend.deltaPercent, trend.isUp, delta >= 10 {
            answer += " It's also up \(Int(delta.rounded()))% from last month, so it's worth a look."
        } else if categories.count > 1 {
            answer += " \(categories[1].name) is next at \(money(categories[1].total))."
        }
        return answer
    }

    private func affordabilityAnswer(_ analytics: ExpenseAnalytics) -> String {
        let month = analytics.aggregate(in: analytics.currentMonth)
        let lastMonth = analytics.aggregate(in: analytics.previousMonth)

        var answer = "I can't set a budget for you, but here's the picture: you're at \(money(month.total)) this month across \(receiptCount(month.count))"
        if lastMonth.total > 0 {
            let pace = month.total <= lastMonth.total ? "under" : "over"
            answer += ", \(pace) last month's \(money(lastMonth.total)) so far."
        } else {
            answer += "."
        }
        return answer
    }

    private func frequencyAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        if let merchant = analytics.matchMerchant(in: query) {
            let visits = analytics.receipts.filter { $0.merchant == merchant }
            return "You've been to \(merchant) \(visitCount(visits.count)), totalling \(money(analytics.aggregate(visits).total))."
        }
        if let category = analytics.matchCategory(in: query) {
            let hits = analytics.receipts.filter { $0.category == category }
            return "You have \(receiptCount(hits.count)) in \(category), totalling \(money(analytics.aggregate(hits).total))."
        }
        return "You've logged \(receiptCount(analytics.receipts.count)) in total. Ask about a specific merchant or category and I'll tell you how often."
    }

    private func whenAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        if let merchant = analytics.matchMerchant(in: query) {
            let visits = analytics.receipts.filter { $0.merchant == merchant }.sorted { $0.date > $1.date }
            guard let latest = visits.first else { return "I don't see any receipts from \(merchant)." }
            return "Your most recent \(merchant) receipt was \(money(latest.amount)) on \(latest.date.formatted(date: .abbreviated, time: .omitted))."
        }
        guard let recent = analytics.mostRecent else { return "No receipts saved yet." }
        return "Your most recent receipt was \(recent.merchant), \(money(recent.amount)) on \(recent.date.formatted(date: .abbreviated, time: .omitted))."
    }

    private func listAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        let (scoped, range) = scope(query, analytics, default: analytics.allTime)
        var receipts = scoped
        var label = range.isAllTime ? "your recent receipts" : "your \(range.label) receipts"

        if let merchant = analytics.matchMerchant(in: query) {
            receipts = receipts.filter { $0.merchant == merchant }
            label = "your \(merchant) receipts"
        } else if let category = analytics.matchCategory(in: query) {
            receipts = receipts.filter { $0.category == category }
            label = "your \(category) receipts"
        }

        let newest = receipts.sorted { $0.date > $1.date }.prefix(5)
        guard newest.isEmpty == false else { return "I couldn't find any receipts matching that." }

        let lines = newest.map { "• \($0.merchant) — \(money($0.amount)) on \($0.date.formatted(date: .abbreviated, time: .omitted))" }
        let more = receipts.count > newest.count ? "\n(showing \(newest.count) of \(receipts.count))" : ""
        return "Here are \(label):\n" + lines.joined(separator: "\n") + more
    }

    private func capabilitiesAnswer() -> String {
        "Ask me anything about your receipts: totals for any month, year, or merchant; category breakdowns; your biggest or average purchase; how this month compares to last; where to cut back; tax paid; or duplicate and unusual charges. Try “how much at Amazon this year?” or “how am I doing this month?”"
    }

    /// Last resort — but never a dead end. If the question still names a period, merchant, or
    /// category, answer that; otherwise give a live snapshot so there's always something useful.
    private func fallbackAnswer(query: String, analytics: ExpenseAnalytics) -> String {
        if let merchant = analytics.matchMerchant(in: query) {
            return merchantAnswer(merchant: merchant, query: query, analytics: analytics)
        }
        if let category = analytics.matchCategory(in: query) {
            return categoryAnswer(category: category, query: query, analytics: analytics)
        }
        if analytics.detectRange(in: query) != nil {
            return totalAnswer(query: query, analytics: analytics)
        }
        return snapshotAnswer(analytics)
    }

    // MARK: - Helpers

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
        matches(query, ["at ", "from ", "how much", "spend", "spent", "total", "pay", "paid", "cost"])
    }

    private func isGreeting(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.count <= 4 else { return false }
        let greetings: Set<String> = ["hi", "hello", "hey", "yo", "hiya", "howdy", "sup"]
        if let first = words.first, greetings.contains(first) { return true }
        return ["good morning", "good afternoon", "good evening"].contains { query.contains($0) }
    }

    private func isThanks(_ query: String) -> Bool {
        let words = query.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard words.count <= 4 else { return false }
        return ["thank", "thanks", "thx", "appreciate", "cheers", "awesome", "perfect", "great job"].contains { query.contains($0) }
    }

    private func matches(_ query: String, _ needles: [String]) -> Bool {
        needles.contains { query.contains($0) }
    }

    private func greetingAnswer(_ analytics: ExpenseAnalytics, seed: String) -> String {
        let month = analytics.aggregate(in: analytics.currentMonth)
        let stat = month.count > 0
            ? " You're at \(money(month.total)) this month so far — ask me anything about it."
            : " Ask me about totals, merchants, categories, or trends whenever you're ready."
        return variant(["Hey there!", "Hi!", "Hello!"], seed: seed) + stat
    }

    /// Picks one of several phrasings deterministically from the question text, so the same
    /// question always answers the same way but different questions don't all sound identical.
    private func variant(_ options: [String], seed: String) -> String {
        guard let first = options.first else { return "" }
        guard options.count > 1 else { return first }
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return options[hash % options.count]
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }

    private func receiptCount(_ count: Int) -> String {
        count == 1 ? "1 receipt" : "\(count) receipts"
    }

    private func visitCount(_ count: Int) -> String {
        switch count {
        case 1: "once"
        case 2: "twice"
        default: "\(count) times"
        }
    }
}

private extension String {
    /// Capitalizes only the first character, leaving the rest untouched — for slotting a
    /// lowercase range label like "this month" into the start of a sentence.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
