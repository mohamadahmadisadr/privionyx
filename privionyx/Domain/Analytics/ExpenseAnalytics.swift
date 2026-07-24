import Foundation

/// The single source of numeric truth about a set of receipts.
///
/// Every assistant engine reasons over the figures this type computes — the deterministic
/// built-in engine answers straight from them, and the language-model engines are handed
/// them as pre-computed facts so a small on-device model never has to sum a column of
/// numbers in its head. A total is calculated once, here, and tested once, here.
struct ExpenseAnalytics {
    let receipts: [AssistantReceipt]
    let referenceDate: Date
    private let calendar: Calendar

    init(receipts: [AssistantReceipt], referenceDate: Date = .now, calendar: Calendar = .current) {
        self.receipts = receipts
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    init(context: AssistantContext, calendar: Calendar = .current) {
        self.init(receipts: context.receipts, referenceDate: context.referenceDate, calendar: calendar)
    }

    var isEmpty: Bool { receipts.isEmpty }

    var mostRecent: AssistantReceipt? {
        receipts.max { $0.date < $1.date }
    }

    // MARK: - Date ranges

    /// A half-open span `[start, end)` with a human label for use in answers.
    struct DateRange: Equatable {
        let start: Date
        /// Exclusive — a receipt at exactly `end` belongs to the next range.
        let end: Date
        let label: String
        /// `true` for the unbounded "everything ever" range.
        let isAllTime: Bool

        func contains(_ date: Date) -> Bool {
            isAllTime || (date >= start && date < end)
        }
    }

    var allTime: DateRange {
        DateRange(start: .distantPast, end: .distantFuture, label: "all time", isAllTime: true)
    }

    func range(of component: Calendar.Component, containing date: Date, label: String) -> DateRange {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return allTime
        }
        return DateRange(start: interval.start, end: interval.end, label: label, isAllTime: false)
    }

    var currentMonth: DateRange {
        range(of: .month, containing: referenceDate, label: "this month")
    }

    var previousMonth: DateRange {
        let date = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
        return range(of: .month, containing: date, label: "last month")
    }

    /// Parses an explicit period out of a free-text question, or `nil` when none is named
    /// (letting each caller pick its own default). Order matters — longer, more specific
    /// phrases are checked before the words they contain.
    func detectRange(in query: String) -> DateRange? {
        let q = query.lowercased()

        if q.contains("all time") || q.contains("ever") || q.contains("overall") || q.contains("in total") || q.contains("altogether") {
            return allTime
        }
        if q.contains("today") {
            return range(of: .day, containing: referenceDate, label: "today")
        }
        if q.contains("yesterday") {
            let date = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            return range(of: .day, containing: date, label: "yesterday")
        }
        if q.contains("last week") || q.contains("past week") {
            let date = calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate) ?? referenceDate
            return range(of: .weekOfYear, containing: date, label: "last week")
        }
        if q.contains("this week") {
            return range(of: .weekOfYear, containing: referenceDate, label: "this week")
        }
        if q.contains("last month") || q.contains("previous month") {
            return previousMonth
        }
        if q.contains("this month") {
            return currentMonth
        }
        if q.contains("last year") || q.contains("previous year") {
            let date = calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate
            return range(of: .year, containing: date, label: "last year")
        }
        if q.contains("this year") {
            return range(of: .year, containing: referenceDate, label: "this year")
        }
        if let named = detectNamedMonth(in: q) {
            return named
        }
        if let year = detectYear(in: q) {
            return year
        }
        return nil
    }

    /// A month name ("june", "in january 2024"), resolved to that month. A bare month with
    /// no year resolves to its most recent past occurrence so "in December" in January means
    /// last month, not eleven months from now.
    private func detectNamedMonth(in query: String) -> DateRange? {
        let symbols = calendar.monthSymbols.map { $0.lowercased() }
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init)

        for (index, symbol) in symbols.enumerated() where tokens.contains(symbol) {
            let month = index + 1
            let referenceYear = calendar.component(.year, from: referenceDate)

            // Prefer an explicit four-digit year adjacent to the month name.
            let explicitYear = tokens.compactMap { Int($0) }.first { (2000...2100).contains($0) }
            var components = DateComponents()
            components.month = month
            components.year = explicitYear ?? referenceYear
            components.day = 1

            guard var date = calendar.date(from: components) else { continue }
            // Bare month that hasn't happened yet this year → assume last year.
            if explicitYear == nil, date > referenceDate {
                date = calendar.date(byAdding: .year, value: -1, to: date) ?? date
            }
            let year = calendar.component(.year, from: date)
            return range(of: .month, containing: date, label: "\(symbol.capitalized) \(year)")
        }
        return nil
    }

    private func detectYear(in query: String) -> DateRange? {
        let tokens = query.split { !$0.isNumber }.map(String.init)
        guard let year = tokens.compactMap({ Int($0) }).first(where: { (2000...2100).contains($0) }) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        guard let date = calendar.date(from: components) else { return nil }
        return range(of: .year, containing: date, label: "\(year)")
    }

    func receipts(in range: DateRange) -> [AssistantReceipt] {
        guard range.isAllTime == false else { return receipts }
        return receipts.filter { range.contains($0.date) }
    }

    // MARK: - Aggregates

    struct Aggregate: Equatable {
        let total: Double
        let count: Int
        var average: Double { count == 0 ? 0 : total / Double(count) }
    }

    func aggregate(_ receipts: [AssistantReceipt]) -> Aggregate {
        Aggregate(total: receipts.reduce(0) { $0 + $1.amount }, count: receipts.count)
    }

    func aggregate(in range: DateRange) -> Aggregate {
        aggregate(receipts(in: range))
    }

    // MARK: - Breakdowns

    /// A named slice of spending (a category, a merchant, a month), pre-sorted by total.
    struct Group: Identifiable, Equatable {
        let name: String
        let total: Double
        let count: Int
        var id: String { name }
    }

    func byCategory(_ receipts: [AssistantReceipt]) -> [Group] {
        grouped(receipts, by: \.category)
    }

    func byMerchant(_ receipts: [AssistantReceipt]) -> [Group] {
        grouped(receipts, by: \.merchant)
    }

    private func grouped(_ receipts: [AssistantReceipt], by key: KeyPath<AssistantReceipt, String>) -> [Group] {
        Dictionary(grouping: receipts, by: { $0[keyPath: key] })
            .map { Group(name: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.total > $1.total }
    }

    /// Spending per calendar month, oldest first.
    func byMonth() -> [Group] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"

        return Dictionary(grouping: receipts) { receipt -> Date in
            calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
        }
        .map { start, group in
            Group(name: formatter.string(from: start), total: group.reduce(0) { $0 + $1.amount }, count: group.count)
        }
        .sorted { $0.name < $1.name }
    }

    // MARK: - Extremes

    func largestPurchase(in receipts: [AssistantReceipt]) -> AssistantReceipt? {
        receipts.max { $0.amount < $1.amount }
    }

    func smallestPurchase(in receipts: [AssistantReceipt]) -> AssistantReceipt? {
        receipts.min { $0.amount < $1.amount }
    }

    // MARK: - Tax

    func tax(in receipts: [AssistantReceipt]) -> (total: Double, taxedCount: Int) {
        let taxed = receipts.compactMap(\.tax).filter { $0 > 0 }
        return (taxed.reduce(0, +), taxed.count)
    }

    // MARK: - Trend

    struct Trend: Equatable {
        let current: Double
        let previous: Double

        /// Percent change vs. the prior period, or `nil` when there's no prior spending to
        /// compare against (so callers don't divide by zero or claim a meaningless "∞% up").
        var deltaPercent: Double? {
            guard previous > 0 else { return nil }
            return ((current - previous) / previous) * 100
        }
        var isUp: Bool { current >= previous }
    }

    /// This month vs. last month, optionally narrowed to a single category.
    func monthOverMonth(category: String? = nil) -> Trend {
        func total(_ range: DateRange) -> Double {
            var slice = receipts(in: range)
            if let category { slice = slice.filter { $0.category == category } }
            return slice.reduce(0) { $0 + $1.amount }
        }
        return Trend(current: total(currentMonth), previous: total(previousMonth))
    }

    // MARK: - Anomalies

    struct Anomaly: Equatable {
        let receipt: AssistantReceipt
        /// How many times the category's typical spend this purchase represents.
        let timesTypical: Double
    }

    /// Purchases that stand out as unusually large for their category. Only categories with
    /// enough history to have a meaningful baseline are considered, so a lone receipt is
    /// never flagged as an outlier against itself.
    func anomalies(threshold: Double = 2.0, minimumCategorySize: Int = 3) -> [Anomaly] {
        var results: [Anomaly] = []

        for group in Dictionary(grouping: receipts, by: \.category).values where group.count >= minimumCategorySize {
            let average = group.reduce(0) { $0 + $1.amount } / Double(group.count)
            guard average > 0 else { continue }
            for receipt in group where receipt.amount >= average * threshold {
                results.append(Anomaly(receipt: receipt, timesTypical: receipt.amount / average))
            }
        }
        return results.sorted { $0.timesTypical > $1.timesTypical }
    }

    // MARK: - Duplicates

    struct DuplicatePair: Equatable {
        let merchant: String
        let amount: Double
        let first: Date
        let second: Date
    }

    /// The same merchant charging the same amount within a few days — a likely double charge.
    func duplicates(withinDays days: Double = 3) -> [DuplicatePair] {
        var results: [DuplicatePair] = []

        for group in Dictionary(grouping: receipts, by: \.merchant).values {
            let sorted = group.sorted { $0.date < $1.date }
            for (index, receipt) in sorted.enumerated() {
                for other in sorted.dropFirst(index + 1) {
                    // Ascending by date, so once one receipt is past the window every
                    // later one is too. Without this the inner loop walked a merchant's
                    // entire history for each of its receipts, comparing pairs years apart.
                    let daysApart = other.date.timeIntervalSince(receipt.date) / 86_400
                    guard daysApart <= days else { break }

                    guard abs(receipt.amount - other.amount) < 0.01 else { continue }
                    results.append(DuplicatePair(merchant: receipt.merchant, amount: receipt.amount, first: receipt.date, second: other.date))
                }
            }
        }
        return results
    }

    // MARK: - Lookups

    /// The canonical merchant name mentioned in a question, matched case- and
    /// punctuation-insensitively so "how much at mcdonalds" finds "McDon's #4821".
    func matchMerchant(in query: String) -> String? {
        let normalizedQuery = normalize(query)
        let merchants = Set(receipts.map(\.merchant))

        // Prefer the longest merchant name that appears, so "Whole Foods" wins over "Foods".
        return merchants
            .filter { merchant in
                let normalized = normalize(merchant)
                guard normalized.isEmpty == false else { return false }
                return normalizedQuery.contains(normalized) || firstWordMatches(normalized, in: normalizedQuery)
            }
            .max { normalize($0).count < normalize($1).count }
    }

    /// The category a question is about — a direct name match first (so custom categories
    /// work with no synonym list), then a small everyday-language synonym table.
    func matchCategory(in query: String) -> String? {
        let q = query.lowercased()
        let categories = Set(receipts.map(\.category))

        if let direct = categories.first(where: { q.contains($0.lowercased()) }) {
            return direct
        }

        let synonyms: [String: [String]] = [
            "Dining": ["food", "eat", "restaurant", "restaurants", "coffee", "lunch", "dinner", "breakfast", "takeout"],
            "Grocery": ["groceries", "supermarket", "grocery"],
            "Groceries": ["grocery", "supermarket"],
            "Travel": ["flight", "flights", "hotel", "hotels", "trip", "airfare", "airbnb"],
            "Gas": ["fuel", "petrol", "gasoline"],
            "Fuel": ["gas", "petrol", "gasoline"],
            "Shopping": ["shop", "retail", "clothes", "clothing", "amazon"],
            "Utilities": ["bill", "bills", "electric", "electricity", "internet", "water", "phone"],
            "Entertainment": ["movie", "movies", "streaming", "netflix", "games", "concert"],
            "Health": ["pharmacy", "doctor", "medical", "medicine", "gym", "fitness"]
        ]

        for (category, words) in synonyms where categories.contains(category) {
            if words.contains(where: { q.contains($0) }) { return category }
        }
        return nil
    }

    private func firstWordMatches(_ merchant: String, in query: String) -> Bool {
        guard let firstWord = merchant.split(separator: " ").first, firstWord.count >= 4 else { return false }
        return query.contains(firstWord)
    }

    private func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
    }
}
