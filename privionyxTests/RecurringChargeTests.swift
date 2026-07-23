import Foundation
import Testing
@testable import privionyx

@Suite("Recurring charge detection")
struct RecurringChargeTests {
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    /// A receipt `daysAgo` before the reference date.
    private func receipt(_ merchant: String, _ amount: Double, daysAgo: Int, category: String = "Entertainment") -> AssistantReceipt {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: reference)!
        return AssistantReceipt(id: UUID(), merchant: merchant, amount: amount, tax: nil, date: date, category: category)
    }

    private func analytics(_ receipts: [AssistantReceipt]) -> ExpenseAnalytics {
        ExpenseAnalytics(receipts: receipts, referenceDate: reference)
    }

    @Test("A steady monthly charge is detected as monthly")
    func monthly() {
        let a = analytics([
            receipt("Netflix", 15.99, daysAgo: 2),
            receipt("Netflix", 15.99, daysAgo: 32),
            receipt("Netflix", 15.99, daysAgo: 61)
        ])
        let charge = a.recurringCharges().first
        #expect(charge?.merchant == "Netflix")
        #expect(charge?.cadence == .monthly)
        #expect(charge?.occurrences == 3)
    }

    @Test("A weekly charge is detected and its monthly-equivalent scales up")
    func weekly() {
        let a = analytics([
            receipt("Gym", 10, daysAgo: 1),
            receipt("Gym", 10, daysAgo: 8),
            receipt("Gym", 10, daysAgo: 15),
            receipt("Gym", 10, daysAgo: 22)
        ])
        let charge = a.recurringCharges().first
        #expect(charge?.cadence == .weekly)
        // ~4.34 weeks per month → about $43/mo.
        #expect((charge?.monthlyEquivalent ?? 0) > 40)
    }

    @Test("Irregular spacing is not recurring")
    func irregular() {
        let a = analytics([
            receipt("Random", 20, daysAgo: 1),
            receipt("Random", 20, daysAgo: 9),
            receipt("Random", 20, daysAgo: 70)
        ])
        #expect(a.recurringCharges().isEmpty)
    }

    @Test("Wildly varying amounts are not a subscription")
    func varyingAmounts() {
        let a = analytics([
            receipt("Store", 12, daysAgo: 2),
            receipt("Store", 80, daysAgo: 32),
            receipt("Store", 45, daysAgo: 61)
        ])
        #expect(a.recurringCharges().isEmpty)
    }

    @Test("Fewer than the minimum occurrences is not enough")
    func tooFew() {
        let a = analytics([
            receipt("Spotify", 9.99, daysAgo: 2),
            receipt("Spotify", 9.99, daysAgo: 32)
        ])
        #expect(a.recurringCharges().isEmpty)
    }

    @Test("The monthly total sums each subscription's monthly cost")
    func monthlyTotal() {
        let a = analytics([
            receipt("Netflix", 16, daysAgo: 2),
            receipt("Netflix", 16, daysAgo: 32),
            receipt("Netflix", 16, daysAgo: 61),
            receipt("iCloud", 3, daysAgo: 3, category: "Bills"),
            receipt("iCloud", 3, daysAgo: 33, category: "Bills"),
            receipt("iCloud", 3, daysAgo: 62, category: "Bills")
        ])
        #expect(a.recurringCharges().count == 2)
        #expect(a.recurringMonthlyTotal() == 19) // 16 + 3, both monthly
    }
}
