import Foundation
import Testing
@testable import privionyx

@Suite("Expense insights")
struct ExpenseInsightsTests {
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    private func receipt(
        merchant: String,
        amount: Double,
        category: String = "Dining",
        month: Int = 6,
        day: Int = 10
    ) -> AssistantReceipt {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        return AssistantReceipt(id: UUID(), merchant: merchant, amount: amount, tax: nil, date: date, category: category)
    }

    private func context(_ receipts: [AssistantReceipt]) -> AssistantContext {
        AssistantContext(receipts: receipts, currencyCode: "USD", referenceDate: reference)
    }

    @Test("No receipts means no insights")
    func empty() {
        #expect(ExpenseInsights.generate(for: context([])).isEmpty)
    }

    @Test("A likely duplicate is surfaced first and flagged as an alert")
    func duplicateRanksFirst() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "Shop", amount: 25, day: 10),
            receipt(merchant: "Shop", amount: 25, day: 11),
            receipt(merchant: "Other", amount: 5, day: 12)
        ]))
        #expect(insights.first?.id == "duplicates")
        #expect(insights.first?.tone == .alert)
    }

    @Test("A calm month still yields at least a neutral fact")
    func neutralFallback() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "A", amount: 10),
            receipt(merchant: "B", amount: 12)
        ]))
        #expect(insights.isEmpty == false)
        #expect(insights.allSatisfy { $0.tone == .neutral })
    }

    @Test("Falling spending reads as positive")
    func spendingDownIsPositive() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "A", amount: 40, month: 6, day: 5),
            receipt(merchant: "B", amount: 200, month: 5, day: 5)
        ]))
        #expect(insights.contains { $0.id == "trend" && $0.tone == .positive })
    }

    @Test("Going over budget leads the insights as an alert")
    func overBudgetLeads() {
        let insights = ExpenseInsights.generate(
            for: context([
                receipt(merchant: "Cafe", amount: 350, category: "Dining"),
                receipt(merchant: "Air", amount: 50, category: "Travel")
            ]),
            budgets: ["Dining": 300]
        )
        #expect(insights.first?.id == "budget-over")
        #expect(insights.first?.tone == .alert)
    }

    @Test("Nearing a budget warns without claiming an overage")
    func nearBudgetWarns() {
        let insights = ExpenseInsights.generate(
            for: context([receipt(merchant: "Cafe", amount: 270, category: "Dining")]),
            budgets: ["Dining": 300]
        )
        #expect(insights.contains { $0.id == "budget-near" })
    }

    @Test("With no budgets set, no budget insight appears")
    func noBudgetNoInsight() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "Cafe", amount: 350, category: "Dining")
        ]))
        #expect(insights.contains { $0.id.hasPrefix("budget") } == false)
    }

    @Test("Recurring charges surface as an insight")
    func recurringInsight() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "Netflix", amount: 16, category: "Entertainment", month: 6, day: 2),
            receipt(merchant: "Netflix", amount: 16, category: "Entertainment", month: 5, day: 3),
            receipt(merchant: "Netflix", amount: 16, category: "Entertainment", month: 4, day: 4)
        ]), limit: 8)
        #expect(insights.contains { $0.id == "recurring" })
    }

    @Test("The list is capped at the requested limit")
    func respectsLimit() {
        let insights = ExpenseInsights.generate(for: context([
            receipt(merchant: "Shop", amount: 25, day: 10),
            receipt(merchant: "Shop", amount: 25, day: 11),
            receipt(merchant: "Cafe", amount: 10, category: "Dining"),
            receipt(merchant: "Air", amount: 300, category: "Travel")
        ]), limit: 2)
        #expect(insights.count <= 2)
    }
}
