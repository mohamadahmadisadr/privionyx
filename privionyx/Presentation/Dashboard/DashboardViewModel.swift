import SwiftUI

/// Derived figures for the Dashboard.
///
/// A reference type, and deliberately so: every screen section asks it a different question
/// about the same receipts, and `body` re-runs whenever the period changes. As a struct
/// there was nowhere to keep an answer, so each render recomputed the lot — `categorySummaries`
/// scanned the array once per category, and recurring-charge detection ran three times over.
///
/// Everything here is memoised for the life of the instance, which is exactly the life of one
/// `receipts` array: `PrivionyxRootView` builds a new view model whenever the receipts change,
/// so a cached answer can never go stale.
@MainActor
final class DashboardViewModel {
    let receipts: [ReceiptItem]
    private let budgetStore: MonthlyBudgetStore

    private var receiptsInPeriod: [DashboardPeriod: [ReceiptItem]] = [:]
    private var receiptsInPreviousPeriod: [DashboardPeriod: [ReceiptItem]] = [:]
    private var categorySummariesByPeriod: [DashboardPeriod: [CategorySummary]] = [:]
    private var chartPointsByPeriod: [DashboardPeriod: [SpendingChartPoint]] = [:]
    private var cachedInsights: [Int: [ExpenseInsight]] = [:]
    private var cachedBudgetProgress: [BudgetProgress]?
    private var cachedRecurringCharges: [RecurringCharge]?

    /// Built once. Constructing it maps the whole receipts array, and it was previously
    /// rebuilt by every caller that needed analytics.
    private lazy var analytics = ExpenseAnalytics(context: AssistantContext(receipts: receipts))

    init(receipts: [ReceiptItem], budgetStore: MonthlyBudgetStore = MonthlyBudgetStore()) {
        self.receipts = receipts
        self.budgetStore = budgetStore
    }

    func totalSpent(for period: DashboardPeriod) -> String {
        let total = receipts(in: period).reduce(0) { $0 + $1.amount }
        return PrivionyxCurrencyFormatter.string(for: total)
    }

    func averageReceiptValue(for period: DashboardPeriod) -> String {
        let scopedReceipts = receipts(in: period)
        guard scopedReceipts.isEmpty == false else { return PrivionyxCurrencyFormatter.string(for: 0) }
        let average = scopedReceipts.reduce(0) { $0 + $1.amount } / Double(scopedReceipts.count)
        return PrivionyxCurrencyFormatter.string(for: average)
    }

    func leadingCategory(for period: DashboardPeriod) -> String {
        let grouped = Dictionary(grouping: receipts(in: period), by: \.category)
        return grouped
            .max { lhs, rhs in
                lhs.value.reduce(0) { $0 + $1.amount } < rhs.value.reduce(0) { $0 + $1.amount }
            }?
            .key
            .rawValue ?? "None"
    }

    func largestReceiptValue(for period: DashboardPeriod) -> String {
        let value = receipts(in: period).map(\.amount).max() ?? 0
        return PrivionyxCurrencyFormatter.string(for: value)
    }

    /// Time-of-day greeting shown above the screen title.
    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// Whole-percent change against the previous period, or `nil` when there is no
    /// prior period to compare against.
    func comparisonPercentage(for period: DashboardPeriod) -> Int? {
        let current = receipts(in: period).reduce(0) { $0 + $1.amount }
        let previous = receipts(inPrevious: period).reduce(0) { $0 + $1.amount }
        guard previous > 0 else { return nil }
        return Int((((current - previous) / previous) * 100).rounded())
    }

    /// Each category's share of the period total, largest first. Bars alternate between
    /// the accent and a muted tone by rank rather than carrying a per-category hue, which
    /// keeps the stack readable instead of rainbow-coloured.
    func categoryShares(for period: DashboardPeriod) -> [CategoryShare] {
        let summaries = categorySummaries(for: period)
        let total = summaries.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        return summaries
            .sorted { $0.amount > $1.amount }
            .enumerated()
            .map { index, summary in
                CategoryShare(
                    name: summary.category,
                    share: summary.amount / total,
                    color: Self.seriesColor(at: index)
                )
            }
    }

    /// Alternating accent / muted tone used by ranked series.
    static func seriesColor(at index: Int) -> Color {
        index.isMultiple(of: 2) ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.mutedSeries
    }

    /// Amounts for the summary sparkline.
    func sparklineValues(for period: DashboardPeriod) -> [Double] {
        chartPoints(for: period).map(\.amount)
    }

    func recentReceipts(limit: Int = 5) -> [ReceiptItem] {
        receipts.sorted { $0.date > $1.date }.prefix(limit).map { $0 }
    }

    /// Automatically-surfaced observations (spikes, anomalies, duplicates, trends) shown as
    /// cards at the top of the Dashboard so the numbers speak up without being asked.
    func insights(limit: Int = 3) -> [ExpenseInsight] {
        if let cached = cachedInsights[limit] { return cached }

        let generated = ExpenseInsights.generate(
            for: analytics,
            budgets: budgetStore.budgetsByName(),
            limit: limit
        )
        cachedInsights[limit] = generated
        return generated
    }

    /// This month's progress against each set budget, most-consumed first. Empty when the
    /// user hasn't set any budgets, so the Dashboard hides the section entirely.
    func budgetProgress() -> [BudgetProgress] {
        if let cachedBudgetProgress { return cachedBudgetProgress }

        let progress = analytics.budgetProgress(budgets: budgetStore.budgetsByName())
        cachedBudgetProgress = progress
        return progress
    }

    /// Detected subscriptions and recurring bills, priciest per month first.
    ///
    /// Cached because detection groups and sorts every receipt, and the Dashboard asks for
    /// this twice in one pass — once for the subscriptions card, once by way of `insights()`.
    func recurringCharges() -> [RecurringCharge] {
        if let cachedRecurringCharges { return cachedRecurringCharges }

        let charges = analytics.recurringCharges()
        cachedRecurringCharges = charges
        return charges
    }

    func comparisonText(for period: DashboardPeriod) -> String {
        let current = receipts(in: period).reduce(0) { $0 + $1.amount }
        let previous = receipts(inPrevious: period).reduce(0) { $0 + $1.amount }

        guard previous > 0 else {
            return current > 0 ? "New" : "$0"
        }

        let delta = ((current - previous) / previous) * 100
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Int(delta.rounded()))%"
    }

    func categorySummaries(for period: DashboardPeriod) -> [CategorySummary] {
        if let cached = categorySummariesByPeriod[period] { return cached }

        // One pass, rather than a full scan per category.
        var totals: [ReceiptCategory: Double] = [:]
        for receipt in receipts(in: period) {
            totals[receipt.category, default: 0] += receipt.amount
        }

        // Still driven by `allCases` so the order stays the declaration order.
        let summaries = ReceiptCategory.allCases.compactMap { category -> CategorySummary? in
            guard let amount = totals[category], amount > 0 else { return nil }
            return CategorySummary(category: category.rawValue, amount: amount, color: color(for: category))
        }

        categorySummariesByPeriod[period] = summaries
        return summaries
    }

    func topMerchants(for period: DashboardPeriod) -> [MerchantSummary] {
        Dictionary(grouping: receipts(in: period), by: \.merchant)
            .map { merchant, receipts in
                MerchantSummary(
                    name: merchant,
                    amount: receipts.reduce(0) { $0 + $1.amount },
                    receiptCount: receipts.count
                )
            }
            .sorted {
                if $0.amount == $1.amount {
                    return $0.receiptCount > $1.receiptCount
                }
                return $0.amount > $1.amount
            }
            .prefix(4)
            .map { $0 }
    }

    func topMerchantName(for period: DashboardPeriod) -> String {
        topMerchants(for: period).first?.name ?? "None"
    }

    func topMerchantValue(for period: DashboardPeriod) -> String {
        guard let merchant = topMerchants(for: period).first else {
            return PrivionyxCurrencyFormatter.string(for: 0)
        }
        return PrivionyxCurrencyFormatter.string(for: merchant.amount)
    }

    func weekdaySummaries(for period: DashboardPeriod) -> [WeekdaySummary] {
        let calendar = Calendar.current

        // One pass rather than one per weekday, which also computes each receipt's weekday
        // once instead of seven times.
        var totals: [Int: Double] = [:]
        for receipt in receipts(in: period) {
            totals[calendar.component(.weekday, from: receipt.date), default: 0] += receipt.amount
        }

        return calendar.shortWeekdaySymbols.enumerated().map { index, symbol in
            WeekdaySummary(label: symbol, amount: totals[index + 1] ?? 0)
        }
    }

    func strongestWeekday(for period: DashboardPeriod) -> String {
        weekdaySummaries(for: period).max(by: { $0.amount < $1.amount })?.label ?? "None"
    }

    func weekdaySummaryText(for period: DashboardPeriod) -> String {
        let summaries = weekdaySummaries(for: period)
        guard let peak = summaries.max(by: { $0.amount < $1.amount }),
              let low = summaries.filter({ $0.amount > 0 }).min(by: { $0.amount < $1.amount }) else {
            return "Save more receipts to reveal weekday spending patterns."
        }

        return "\(peak.label) is your strongest spending day, while \(low.label) is currently the lightest."
    }

    func monthlyDeltaPoints() -> [MonthlyDeltaPoint] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateFormat = "MMM"

        let months = (0..<6).compactMap { monthOffset in
            calendar.date(byAdding: .month, value: -(5 - monthOffset), to: .now)
        }

        var previousAmount: Double?

        return months.map { month in
            let currentAmount = receipts
                .filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }

            let delta = previousAmount.map { currentAmount - $0 } ?? 0
            previousAmount = currentAmount

            return MonthlyDeltaPoint(label: formatter.string(from: month), delta: delta)
        }
    }

    func monthlyDeltaSummaryText() -> String {
        let points = monthlyDeltaPoints().dropFirst()
        guard let strongestRise = points.max(by: { $0.delta < $1.delta }),
              let strongestDrop = points.min(by: { $0.delta < $1.delta }) else {
            return "Monthly deltas will appear once multiple months of receipts are saved."
        }

        return "Biggest increase: \(strongestRise.label) at \(PrivionyxCurrencyFormatter.string(for: strongestRise.delta)). Biggest drop: \(strongestDrop.label) at \(PrivionyxCurrencyFormatter.string(for: abs(strongestDrop.delta)))."
    }

    func categoryComparisons(for period: DashboardPeriod) -> [CategoryComparison] {
        // Two passes total rather than two per category.
        var currentTotals: [ReceiptCategory: Double] = [:]
        for receipt in receipts(in: period) {
            currentTotals[receipt.category, default: 0] += receipt.amount
        }
        var previousTotals: [ReceiptCategory: Double] = [:]
        for receipt in receipts(inPrevious: period) {
            previousTotals[receipt.category, default: 0] += receipt.amount
        }

        let totals = ReceiptCategory.allCases.compactMap { category -> CategoryComparison? in
            let currentAmount = currentTotals[category] ?? 0
            let previousAmount = previousTotals[category] ?? 0

            guard currentAmount > 0 || previousAmount > 0 else { return nil }

            let delta = currentAmount - previousAmount
            let maxAmount = max(currentAmount, 1)

            return CategoryComparison(
                category: category.rawValue,
                currentAmount: currentAmount,
                previousAmount: previousAmount,
                delta: delta,
                share: min(1, currentAmount / maxAmount),
                color: color(for: category)
            )
        }

        return totals.sorted { abs($0.delta) > abs($1.delta) }.prefix(4).map { $0 }
    }

    func trendSummary(for period: DashboardPeriod) -> [String] {
        var lines: [String] = []
        let currentReceipts = receipts(in: period)

        if let merchant = topMerchants(for: period).first {
            lines.append("\(merchant.name) leads \(period.shortTitle.lowercased()) spending at \(PrivionyxCurrencyFormatter.string(for: merchant.amount)).")
        }

        if let category = categoryComparisons(for: period).first {
            let direction = category.delta >= 0 ? "up" : "down"
            lines.append("\(category.category) is \(direction) \(category.deltaText) versus the previous period.")
        }

        if let peakBucket = chartPoints(for: period).max(by: { $0.amount < $1.amount }), peakBucket.amount > 0 {
            lines.append("Peak trend bucket is \(peakBucket.label) with \(PrivionyxCurrencyFormatter.string(for: peakBucket.amount)).")
        }

        if currentReceipts.count >= 3 {
            lines.append("You have \(currentReceipts.count) receipts in this range with an average of \(averageReceiptValue(for: period)).")
        }

        return lines.isEmpty ? ["Save more receipts to unlock richer spending analytics."] : lines
    }

    func chartPoints(for period: DashboardPeriod) -> [SpendingChartPoint] {
        if let cached = chartPointsByPeriod[period] { return cached }

        let points = computeChartPoints(for: period)
        chartPointsByPeriod[period] = points
        return points
    }

    private func computeChartPoints(for period: DashboardPeriod) -> [SpendingChartPoint] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        switch period {
        case .daily:
            let last7Days = (0..<7).compactMap { dayOffset in
                calendar.date(byAdding: .day, value: -(6 - dayOffset), to: calendar.startOfDay(for: .now))
            }
            let recentPoints = dailyPoints(for: last7Days, formatter: formatter, calendar: calendar)

            if recentPoints.contains(where: { $0.amount > 0 }) {
                return recentPoints
            }

            let fallbackDays = Array(
                Set(receipts.map { calendar.startOfDay(for: $0.date) })
            )
            .sorted()
            .suffix(7)

            return dailyPoints(for: Array(fallbackDays), formatter: formatter, calendar: calendar)

        case .monthly:
            let months = (0..<6).compactMap { monthOffset in
                calendar.date(byAdding: .month, value: -(5 - monthOffset), to: .now)
            }

            formatter.dateFormat = "MMM"
            return months.map { month in
                let amount = receipts
                    .filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
                    .reduce(0) { $0 + $1.amount }
                return SpendingChartPoint(label: formatter.string(from: month), amount: amount)
            }

        case .yearly:
            let years = (0..<5).compactMap { yearOffset in
                calendar.date(byAdding: .year, value: -(4 - yearOffset), to: .now)
            }

            formatter.dateFormat = "yyyy"
            return years.map { year in
                let amount = receipts
                    .filter { calendar.isDate($0.date, equalTo: year, toGranularity: .year) }
                    .reduce(0) { $0 + $1.amount }
                return SpendingChartPoint(label: formatter.string(from: year), amount: amount)
            }
        }
    }

    private func dailyPoints(
        for days: [Date],
        formatter: DateFormatter,
        calendar: Calendar
    ) -> [SpendingChartPoint] {
        formatter.dateFormat = "EEE"

        return days.map { day in
            let amount = receipts
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.amount }
            return SpendingChartPoint(label: formatter.string(from: day), amount: amount)
        }
    }

    private func receipts(in period: DashboardPeriod) -> [ReceiptItem] {
        if let cached = receiptsInPeriod[period] { return cached }

        let scoped = computeReceipts(in: period)
        receiptsInPeriod[period] = scoped
        return scoped
    }

    private func receipts(inPrevious period: DashboardPeriod) -> [ReceiptItem] {
        if let cached = receiptsInPreviousPeriod[period] { return cached }

        let scoped = computeReceipts(inPrevious: period)
        receiptsInPreviousPeriod[period] = scoped
        return scoped
    }

    private func computeReceipts(in period: DashboardPeriod) -> [ReceiptItem] {
        let calendar = Calendar.current

        switch period {
        case .daily:
            guard let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) else {
                return []
            }
            let endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
            return receipts.filter { $0.date >= startDate && $0.date <= endDate }
        case .monthly:
            return receipts.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
        case .yearly:
            return receipts.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .year) }
        }
    }

    private func computeReceipts(inPrevious period: DashboardPeriod) -> [ReceiptItem] {
        let calendar = Calendar.current

        switch period {
        case .daily:
            guard let endDate = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)),
                  let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: endDate)) else {
                return []
            }
            let previousRangeEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
            return receipts.filter { $0.date >= startDate && $0.date <= previousRangeEnd }
        case .monthly:
            guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: .now) else { return [] }
            return receipts.filter { calendar.isDate($0.date, equalTo: previousMonth, toGranularity: .month) }
        case .yearly:
            guard let previousYear = calendar.date(byAdding: .year, value: -1, to: .now) else { return [] }
            return receipts.filter { calendar.isDate($0.date, equalTo: previousYear, toGranularity: .year) }
        }
    }

    private func color(for category: ReceiptCategory) -> Color {
        switch category {
        case .housing:
            Color.brown
        case .bills:
            Color.teal
        case .gas:
            PrivionyxTheme.Colors.warning
        case .grocery:
            PrivionyxTheme.Colors.success
        case .dining:
            PrivionyxTheme.Colors.accent
        case .travel:
            Color.indigo
        case .utilities:
            Color.cyan
        case .health:
            Color.red
        case .entertainment:
            Color.purple
        case .shopping:
            Color.pink
        }
    }
}

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case daily
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            "Last 7 Days"
        case .monthly:
            "This Month"
        case .yearly:
            "This Year"
        }
    }

    var shortTitle: String {
        switch self {
        case .daily:
            "Daily"
        case .monthly:
            "Monthly"
        case .yearly:
            "Yearly"
        }
    }
}

// These are recomputed whenever the Dashboard re-renders, so their identity has to come
// from what they describe. A fresh `UUID()` per instance meant every rebuild produced a set
// SwiftUI considered entirely new, and `ForEach` tore the rows down and rebuilt them rather
// than diffing — losing animation and reusable views on something as ordinary as switching
// the period. Each key below is unique within the collection it appears in.

struct SpendingChartPoint: Identifiable {
    /// Deliberately not the label: the daily fallback series takes the last seven days that
    /// actually have receipts, which can span more than a week and repeat a weekday name.
    /// Nothing puts these in a `ForEach` today; a stable id would need the bucket's date.
    let id = UUID()
    let label: String
    let amount: Double
}

struct CategorySummary: Identifiable {
    /// One entry per category.
    var id: String { category }
    let category: String
    let amount: Double
    let color: Color
}

struct CategoryShare: Identifiable {
    /// One entry per category.
    var id: String { name }
    let name: String
    /// Fraction of the period's total spending, 0...1.
    let share: Double
    let color: Color
}

struct MerchantSummary: Identifiable {
    /// Built by grouping on merchant, so one entry per name.
    var id: String { name }
    let name: String
    let amount: Double
    let receiptCount: Int
}

struct WeekdaySummary: Identifiable {
    /// One entry per weekday symbol.
    var id: String { label }
    let label: String
    let amount: Double
}

struct MonthlyDeltaPoint: Identifiable {
    /// Six consecutive months, so the abbreviated name doesn't repeat.
    var id: String { label }
    let label: String
    let delta: Double
}

struct CategoryComparison: Identifiable {
    /// One entry per category.
    var id: String { category }
    let category: String
    let currentAmount: Double
    let previousAmount: Double
    let delta: Double
    let share: Double
    let color: Color

    var deltaText: String {
        let sign = delta >= 0 ? "+" : "-"
        return "\(sign)\(PrivionyxCurrencyFormatter.string(for: abs(delta)))"
    }
}
