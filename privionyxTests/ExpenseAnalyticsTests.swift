import Foundation
import Testing
@testable import privionyx

@Suite("Expense analytics")
struct ExpenseAnalyticsTests {
    /// A fixed reference date so month/year math is deterministic regardless of when tests run.
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    private func receipt(
        merchant: String,
        amount: Double,
        tax: Double? = nil,
        category: String = "Dining",
        year: Int = 2026,
        month: Int = 6,
        day: Int = 10
    ) -> AssistantReceipt {
        let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
        return AssistantReceipt(id: UUID(), merchant: merchant, amount: amount, tax: tax, date: date, category: category)
    }

    private func analytics(_ receipts: [AssistantReceipt]) -> ExpenseAnalytics {
        ExpenseAnalytics(receipts: receipts, referenceDate: reference)
    }

    // MARK: - Aggregates

    @Test("Totals and averages sum correctly")
    func aggregate() {
        let a = analytics([
            receipt(merchant: "A", amount: 10),
            receipt(merchant: "B", amount: 20),
            receipt(merchant: "C", amount: 30)
        ])
        let agg = a.aggregate(a.receipts)
        #expect(agg.total == 60)
        #expect(agg.count == 3)
        #expect(agg.average == 20)
    }

    @Test("Empty aggregate has a zero average, not a divide-by-zero")
    func emptyAggregate() {
        let a = analytics([])
        let agg = a.aggregate(a.receipts)
        #expect(agg.total == 0)
        #expect(agg.count == 0)
        #expect(agg.average == 0)
    }

    // MARK: - Ranges

    @Test("This month excludes last month's receipts")
    func currentMonthRange() {
        let a = analytics([
            receipt(merchant: "June", amount: 10, month: 6, day: 5),
            receipt(merchant: "May", amount: 99, month: 5, day: 20)
        ])
        let june = a.aggregate(in: a.currentMonth)
        #expect(june.total == 10)
        #expect(june.count == 1)
    }

    @Test("Previous month is the month before the reference date")
    func previousMonthRange() {
        let a = analytics([
            receipt(merchant: "June", amount: 10, month: 6, day: 5),
            receipt(merchant: "May", amount: 40, month: 5, day: 20)
        ])
        #expect(a.aggregate(in: a.previousMonth).total == 40)
    }

    @Test("Natural-language ranges resolve", arguments: [
        ("this month", 6, 2026),
        ("last month", 5, 2026),
        ("this year", 1, 2026),
        ("in 2024", 1, 2024)
    ])
    func detectRange(query: String, month: Int, year: Int) {
        let a = analytics([receipt(merchant: "X", amount: 1)])
        let range = a.detectRange(in: query)
        #expect(range != nil)
        if let range, range.isAllTime == false {
            let comps = Calendar.current.dateComponents([.year], from: range.start)
            #expect(comps.year == year)
        }
    }

    @Test("A bare month name resolves to its most recent past occurrence")
    func namedMonthInPast() {
        // Reference is June 2026; "December" hasn't happened in 2026 yet → December 2025.
        let a = analytics([receipt(merchant: "X", amount: 1)])
        let range = a.detectRange(in: "how much in december")
        #expect(range?.label == "December 2025")
    }

    @Test("No named period returns nil so callers pick their own default")
    func noRange() {
        let a = analytics([receipt(merchant: "X", amount: 1)])
        #expect(a.detectRange(in: "how much did i spend") == nil)
    }

    // MARK: - Breakdowns & extremes

    @Test("Categories rank by total, highest first")
    func categoryRanking() {
        let a = analytics([
            receipt(merchant: "A", amount: 10, category: "Dining"),
            receipt(merchant: "B", amount: 50, category: "Travel"),
            receipt(merchant: "C", amount: 5, category: "Dining")
        ])
        let categories = a.byCategory(a.receipts)
        #expect(categories.first?.name == "Travel")
        #expect(categories.first?.total == 50)
        #expect(categories.last?.name == "Dining")
        #expect(categories.last?.total == 15)
    }

    @Test("Largest and smallest purchases are found")
    func extremes() {
        let a = analytics([
            receipt(merchant: "A", amount: 10),
            receipt(merchant: "B", amount: 99),
            receipt(merchant: "C", amount: 3)
        ])
        #expect(a.largestPurchase(in: a.receipts)?.amount == 99)
        #expect(a.smallestPurchase(in: a.receipts)?.amount == 3)
    }

    // MARK: - Trend

    @Test("Month-over-month reports a percentage change")
    func trend() {
        let a = analytics([
            receipt(merchant: "A", amount: 120, month: 6, day: 5),
            receipt(merchant: "B", amount: 100, month: 5, day: 5)
        ])
        let trend = a.monthOverMonth()
        #expect(trend.current == 120)
        #expect(trend.previous == 100)
        #expect(trend.deltaPercent == 20)
        #expect(trend.isUp)
    }

    @Test("Trend against no prior spending has no percentage")
    func trendNoBaseline() {
        let a = analytics([receipt(merchant: "A", amount: 50, month: 6, day: 5)])
        #expect(a.monthOverMonth().deltaPercent == nil)
    }

    // MARK: - Anomalies & duplicates

    @Test("An outlier well above the category norm is flagged")
    func anomalyFlagged() {
        let a = analytics([
            receipt(merchant: "A", amount: 10, category: "Dining"),
            receipt(merchant: "B", amount: 12, category: "Dining"),
            receipt(merchant: "C", amount: 11, category: "Dining"),
            receipt(merchant: "D", amount: 90, category: "Dining")
        ])
        let anomalies = a.anomalies()
        #expect(anomalies.first?.receipt.merchant == "D")
    }

    @Test("A tiny category with no baseline flags nothing")
    func anomalyNeedsBaseline() {
        let a = analytics([
            receipt(merchant: "A", amount: 10, category: "Dining"),
            receipt(merchant: "B", amount: 500, category: "Travel")
        ])
        #expect(a.anomalies().isEmpty)
    }

    @Test("Same merchant, same amount, within days is a duplicate")
    func duplicates() {
        let a = analytics([
            receipt(merchant: "Shop", amount: 25, day: 10),
            receipt(merchant: "Shop", amount: 25, day: 11),
            receipt(merchant: "Shop", amount: 40, day: 12)
        ])
        let dupes = a.duplicates()
        #expect(dupes.count == 1)
        #expect(dupes.first?.amount == 25)
    }

    @Test("Same amount weeks apart is not a duplicate")
    func notDuplicateWhenFarApart() {
        let a = analytics([
            receipt(merchant: "Shop", amount: 25, day: 1),
            receipt(merchant: "Shop", amount: 25, day: 20)
        ])
        #expect(a.duplicates().isEmpty)
    }

    // MARK: - Lookups

    @Test("Merchant match is case- and punctuation-insensitive")
    func merchantMatch() {
        let a = analytics([receipt(merchant: "Whole Foods Market", amount: 40)])
        #expect(a.matchMerchant(in: "how much at whole foods market") == "Whole Foods Market")
    }

    @Test("Category synonyms map to real categories")
    func categorySynonym() {
        let a = analytics([receipt(merchant: "Cafe", amount: 8, category: "Dining")])
        #expect(a.matchCategory(in: "how much on coffee") == "Dining")
    }
}
