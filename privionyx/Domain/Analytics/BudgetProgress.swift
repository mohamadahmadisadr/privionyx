import Foundation

/// How this month's spending in one category sits against its budget. Pure value type so it
/// can drive a progress bar on the Dashboard and an alert in the insights list from the same
/// numbers.
struct BudgetProgress: Identifiable, Equatable {
    let category: String
    let limit: Double
    let spent: Double

    var id: String { category }

    /// Amount still available before the limit is hit (never negative).
    var remaining: Double { max(0, limit - spent) }
    /// Amount spent beyond the limit (zero unless over).
    var overage: Double { max(0, spent - limit) }
    /// Share of the budget used, unclamped so callers can tell "at 140%" from "at 100%".
    var fraction: Double { limit > 0 ? spent / limit : 0 }
    var isOver: Bool { spent > limit }
    /// Approaching the limit but not past it — the moment worth a heads-up.
    var isNearLimit: Bool { isOver == false && fraction >= 0.8 }
}

extension ExpenseAnalytics {
    /// This month's progress against each provided budget (keyed by category name),
    /// most-consumed first, so the category closest to trouble surfaces at the top.
    func budgetProgress(budgets: [String: Double]) -> [BudgetProgress] {
        let totals = Dictionary(grouping: receipts(in: currentMonth), by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }

        return budgets.compactMap { name, limit -> BudgetProgress? in
            guard limit > 0 else { return nil }
            return BudgetProgress(category: name, limit: limit, spent: totals[name] ?? 0)
        }
        .sorted { $0.fraction > $1.fraction }
    }
}
