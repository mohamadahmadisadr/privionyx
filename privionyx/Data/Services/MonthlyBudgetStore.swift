import Foundation

/// Persists the user's optional monthly spending limit per category. Amounts live in
/// UserDefaults keyed by the category's raw value, mirroring `MerchantRuleService`. A
/// missing or non-positive entry means "no budget set" for that category.
nonisolated struct MonthlyBudgetStore {
    private let defaults: UserDefaults
    private let storageKey = "privionyx.monthly-budgets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func budget(for category: ReceiptCategory) -> Double? {
        guard let value = all()[category.rawValue], value > 0 else { return nil }
        return value
    }

    /// Sets or, when `amount` is nil or non-positive, clears the budget for a category.
    func setBudget(_ amount: Double?, for category: ReceiptCategory) {
        var budgets = all()
        if let amount, amount > 0 {
            budgets[category.rawValue] = amount
        } else {
            budgets.removeValue(forKey: category.rawValue)
        }
        defaults.set(budgets, forKey: storageKey)
    }

    /// Every set budget keyed by category raw value — the shape `ExpenseAnalytics` and
    /// `ExpenseInsights` consume so they stay free of persistence.
    func budgetsByName() -> [String: Double] {
        all().filter { $0.value > 0 }
    }

    private func all() -> [String: Double] {
        defaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
    }
}
