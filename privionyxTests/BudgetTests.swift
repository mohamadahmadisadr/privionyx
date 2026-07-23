import Foundation
import Testing
@testable import privionyx

@Suite("Monthly budgets")
struct BudgetTests {
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    private func store() -> MonthlyBudgetStore {
        // A throwaway suite so tests never touch the real user defaults.
        MonthlyBudgetStore(defaults: UserDefaults(suiteName: "budget-test-\(UUID().uuidString)")!)
    }

    private func receipt(_ amount: Double, category: String = "Dining", day: Int = 10) -> AssistantReceipt {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: day))!
        return AssistantReceipt(id: UUID(), merchant: "M", amount: amount, tax: nil, date: date, category: category)
    }

    private func analytics(_ receipts: [AssistantReceipt]) -> ExpenseAnalytics {
        ExpenseAnalytics(receipts: receipts, referenceDate: reference)
    }

    // MARK: - Store

    @Test("A saved budget reads back")
    func roundTrip() {
        let store = store()
        store.setBudget(300, for: .dining)
        #expect(store.budget(for: .dining) == 300)
        #expect(store.budgetsByName()["Dining"] == 300)
    }

    @Test("Setting nil or zero clears the budget")
    func clearing() {
        let store = store()
        store.setBudget(300, for: .dining)
        store.setBudget(nil, for: .dining)
        #expect(store.budget(for: .dining) == nil)

        store.setBudget(300, for: .travel)
        store.setBudget(0, for: .travel)
        #expect(store.budget(for: .travel) == nil)
    }

    // MARK: - Progress

    @Test("Progress reports spent, remaining, and fraction")
    func progress() {
        let a = analytics([receipt(120, category: "Dining")])
        let progress = a.budgetProgress(budgets: ["Dining": 300]).first
        #expect(progress?.spent == 120)
        #expect(progress?.remaining == 180)
        #expect(progress?.fraction == 0.4)
        #expect(progress?.isOver == false)
    }

    @Test("Overspending is flagged with an overage")
    func overspent() {
        let a = analytics([receipt(350, category: "Dining")])
        let progress = a.budgetProgress(budgets: ["Dining": 300]).first
        #expect(progress?.isOver == true)
        #expect(progress?.overage == 50)
        #expect(progress?.remaining == 0)
    }

    @Test("Approaching the limit is a near-limit warning, not an overage")
    func nearLimit() {
        let a = analytics([receipt(270, category: "Dining")])
        let progress = a.budgetProgress(budgets: ["Dining": 300]).first
        #expect(progress?.isNearLimit == true)
        #expect(progress?.isOver == false)
    }

    @Test("A receipt dated today counts, keyed by base category even with a custom label")
    func realReceiptCountsTowardBaseCategory() {
        let today = ReceiptItem(
            id: UUID(),
            merchant: "Whole Foods",
            amount: 118,
            subtotal: nil,
            tax: nil,
            tip: nil,
            date: .now,
            category: .grocery,
            customCategoryName: "Organic Groceries",
            tags: [],
            imagePath: nil,
            imageData: nil,
            rawText: nil,
            lineItems: [],
            notes: "",
            status: .reviewed
        )
        // The app builds context this way (referenceDate defaults to now).
        let spend = ExpenseAnalytics(context: AssistantContext(receipts: [today]))
            .currentMonthSpendByCategory()

        #expect(spend["Grocery"] == 118)          // base category, so it matches a Grocery budget
        #expect(spend["Organic Groceries"] == nil) // the custom label doesn't split it off
    }

    @Test("The category closest to its limit sorts first")
    func ordering() {
        let a = analytics([
            receipt(90, category: "Dining"),   // 90/100 = 0.9
            receipt(20, category: "Travel")    // 20/100 = 0.2
        ])
        let progress = a.budgetProgress(budgets: ["Dining": 100, "Travel": 100])
        #expect(progress.first?.category == "Dining")
    }
}
