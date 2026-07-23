import Foundation

/// A single automatically-surfaced observation about spending, ready to render as a card.
/// It carries an SF Symbol name and a semantic `tone` rather than a colour, so the domain
/// layer stays free of SwiftUI and the view decides how each tone looks.
struct ExpenseInsight: Identifiable, Equatable {
    enum Tone: Equatable {
        /// Something worth a second look — a spike, an anomaly, a likely duplicate.
        case alert
        /// Good news — spending came down.
        case positive
        /// A plain fact worth showing when nothing needs attention.
        case neutral
    }

    let id: String
    let symbol: String
    let title: String
    let detail: String
    let tone: Tone
}

/// Turns the figures from `ExpenseAnalytics` into a short, prioritised list of insights the
/// Dashboard shows without the user having to ask — the passive counterpart to the
/// assistant. Attention-worthy findings (duplicates, anomalies, spikes) rank above neutral
/// facts, so the most useful card is always first.
enum ExpenseInsights {
    static func generate(
        for context: AssistantContext,
        budgets: [String: Double] = [:],
        limit: Int = 3
    ) -> [ExpenseInsight] {
        let analytics = ExpenseAnalytics(context: context)
        guard analytics.isEmpty == false else { return [] }

        func money(_ value: Double) -> String { PrivionyxCurrencyFormatter.string(for: value) }

        var insights: [ExpenseInsight] = []

        // 0. Budgets — the most actionable signal, so it leads. Show only the single most
        // pressing one (worst overage, else nearest to its limit) to avoid a wall of cards.
        let progress = analytics.budgetProgress(budgets: budgets)
        if let over = progress.first(where: { $0.isOver }) {
            insights.append(ExpenseInsight(
                id: "budget-over",
                symbol: "exclamationmark.circle.fill",
                title: "Over budget on \(over.category)",
                detail: "\(money(over.spent)) of \(money(over.limit)) this month — \(money(over.overage)) over.",
                tone: .alert
            ))
        } else if let near = progress.first(where: { $0.isNearLimit }) {
            insights.append(ExpenseInsight(
                id: "budget-near",
                symbol: "gauge.with.needle.fill",
                title: "\(near.category) nearly at budget",
                detail: "\(money(near.spent)) of \(money(near.limit)) — \(Int((near.fraction * 100).rounded()))% used.",
                tone: .alert
            ))
        }

        // 1. Likely double charges — highest signal, money potentially wasted.
        let duplicates = analytics.duplicates()
        if let first = duplicates.first {
            insights.append(ExpenseInsight(
                id: "duplicates",
                symbol: "doc.on.doc.fill",
                title: duplicates.count == 1 ? "Possible duplicate charge" : "\(duplicates.count) possible duplicates",
                detail: "\(first.merchant) \(money(first.amount)) appears more than once within days.",
                tone: .alert
            ))
        }

        // 2. A purchase far above the norm for its category.
        if let anomaly = analytics.anomalies().first {
            let times = String(format: "%.1f", anomaly.timesTypical)
            insights.append(ExpenseInsight(
                id: "anomaly",
                symbol: "exclamationmark.triangle.fill",
                title: "Unusual purchase",
                detail: "\(anomaly.receipt.merchant) \(money(anomaly.receipt.amount)) — \(times)× your usual \(anomaly.receipt.category.lowercased()).",
                tone: .alert
            ))
        }

        // 3. A category climbing sharply versus last month.
        if let spike = categorySpike(analytics, money: money) {
            insights.append(spike)
        }

        // 4. Overall month-over-month direction.
        let trend = analytics.monthOverMonth()
        if let delta = trend.deltaPercent, abs(delta) >= 10, trend.current > 0 {
            let up = trend.isUp
            insights.append(ExpenseInsight(
                id: "trend",
                symbol: up ? "arrow.up.right" : "arrow.down.right",
                title: up ? "Spending is up this month" : "Spending is down this month",
                detail: "\(money(trend.current)) so far vs \(money(trend.previous)) last month — \(abs(Int(delta.rounded())))% \(up ? "higher" : "lower").",
                tone: up ? .alert : .positive
            ))
        }

        // 5-6. Neutral facts, so there's always something useful even in a calm month.
        let monthReceipts = analytics.receipts(in: analytics.currentMonth)
        if let topCategory = analytics.byCategory(monthReceipts).first {
            let count = topCategory.count == 1 ? "1 receipt" : "\(topCategory.count) receipts"
            insights.append(ExpenseInsight(
                id: "top-category",
                symbol: "chart.pie.fill",
                title: "\(topCategory.name) leads this month",
                detail: "\(money(topCategory.total)) across \(count).",
                tone: .neutral
            ))
        }
        if let biggest = analytics.largestPurchase(in: monthReceipts) {
            insights.append(ExpenseInsight(
                id: "biggest",
                symbol: "star.fill",
                title: "Biggest purchase this month",
                detail: "\(money(biggest.amount)) at \(biggest.merchant).",
                tone: .neutral
            ))
        }

        return Array(insights.prefix(limit))
    }

    /// The category with the largest month-over-month jump, if it's a meaningful one — a
    /// small absolute rise on a tiny base isn't worth alarming anyone about.
    private static func categorySpike(_ analytics: ExpenseAnalytics, money: (Double) -> String) -> ExpenseInsight? {
        let categories = Set(analytics.receipts(in: analytics.currentMonth).map(\.category))

        let spikes = categories.compactMap { category -> (name: String, delta: Double, current: Double)? in
            let trend = analytics.monthOverMonth(category: category)
            guard let delta = trend.deltaPercent, delta >= 25, trend.current - trend.previous >= 20 else { return nil }
            return (category, delta, trend.current)
        }

        guard let top = spikes.max(by: { $0.delta < $1.delta }) else { return nil }
        return ExpenseInsight(
            id: "spike-\(top.name)",
            symbol: "flame.fill",
            title: "\(top.name) is climbing",
            detail: "Up \(Int(top.delta.rounded()))% this month to \(money(top.current)).",
            tone: .alert
        )
    }
}
