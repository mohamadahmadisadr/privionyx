import Charts
import SwiftUI

struct DashboardView: View {
    let viewModel: DashboardViewModel
    @State private var selectedPeriod: DashboardPeriod = .monthly

    var body: some View {
        PrivionyxScreen(
            title: "Dashboard",
            subtitle: "Private spending overview from receipts stored only on this device."
        ) {
            heroSection
            if viewModel.receipts.isEmpty {
                emptyStateSection
            } else {
                metricSection
                summarySection
                trendSection
                if viewModel.categorySummaries(for: selectedPeriod).isEmpty == false {
                    categorySection
                }
                merchantSection
                weekdaySection
                monthlyDeltaSection
                if viewModel.categoryComparisons(for: selectedPeriod).isEmpty == false {
                    categoryComparisonSection
                }
                recentReceiptsSection
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(selectedPeriod.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)

                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.success)
            }

            Text(viewModel.totalSpent(for: selectedPeriod))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(viewModel.receipts.isEmpty ? "Add your first receipt to start building a private spending picture." : "A private spending snapshot from receipts saved on this device.")
                .font(.subheadline)
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            HStack(spacing: 12) {
                InfoPill(title: "Saved", value: "\(viewModel.receipts.count)")
                InfoPill(title: "Change", value: viewModel.comparisonText(for: selectedPeriod))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(PrivionyxTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PrivionyxTheme.Colors.separator, lineWidth: 1)
        )
    }

    private var metricSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            MetricCard(
                title: "Receipts",
                value: "\(viewModel.receipts.count)",
                detail: "Saved in local storage",
                icon: "tray.full.fill",
                tint: PrivionyxTheme.Colors.accent
            )

            MetricCard(
                title: "Top Category",
                value: viewModel.leadingCategory(for: selectedPeriod),
                detail: "Highest spend in selected range",
                icon: "chart.pie.fill",
                tint: PrivionyxTheme.Colors.success
            )

            MetricCard(
                title: "Top Merchant",
                value: viewModel.topMerchantName(for: selectedPeriod),
                detail: viewModel.topMerchantValue(for: selectedPeriod),
                icon: "building.2.fill",
                tint: Color.indigo
            )

            MetricCard(
                title: "Best Day",
                value: viewModel.strongestWeekday(for: selectedPeriod),
                detail: "Highest weekday total",
                icon: "calendar",
                tint: PrivionyxTheme.Colors.warning
            )
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Trend Summary", actionTitle: selectedPeriod.shortTitle)
            ForEach(viewModel.trendSummary(for: selectedPeriod), id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(PrivionyxTheme.Colors.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                }
            }
        }
        .privionyxCardStyle()
    }

    private var emptyStateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Start Here", actionTitle: nil)

            EmptyStateCard(
                systemImage: "doc.text.viewfinder",
                title: "Save a receipt to unlock the dashboard",
                message: "Use the Add tab to scan a paper receipt or import a photo. After review, totals, categories, merchants, and trends will appear here."
            )
        }
        .privionyxCardStyle()
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Spending Trend", actionTitle: selectedPeriod.shortTitle)

            Picker("Period", selection: $selectedPeriod) {
                ForEach(DashboardPeriod.allCases) { period in
                    Text(period.shortTitle).tag(period)
                }
            }
            .pickerStyle(.segmented)

            Chart(viewModel.chartPoints(for: selectedPeriod)) { point in
                BarMark(
                    x: .value("Bucket", point.label),
                    y: .value("Amount", point.amount)
                )
                .foregroundStyle(PrivionyxTheme.Colors.accent.gradient)
                .cornerRadius(6)
            }
            .frame(height: 240)
            .chartYAxis { AxisMarks(position: .leading) }

            HStack(spacing: 12) {
                InfoPill(title: "Largest", value: viewModel.largestReceiptValue(for: selectedPeriod))
                InfoPill(title: "Average", value: viewModel.averageReceiptValue(for: selectedPeriod))
            }
        }
        .privionyxCardStyle()
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Category Mix", actionTitle: selectedPeriod.shortTitle)

            Chart(viewModel.categorySummaries(for: selectedPeriod)) { summary in
                SectorMark(
                    angle: .value("Amount", summary.amount),
                    innerRadius: .ratio(0.58),
                    angularInset: 2
                )
                .foregroundStyle(summary.color)
            }
            .frame(height: 220)

            VStack(spacing: 10) {
                ForEach(viewModel.categorySummaries(for: selectedPeriod).prefix(4)) { summary in
                    HStack {
                        Circle()
                            .fill(summary.color)
                            .frame(width: 10, height: 10)
                        Text(summary.category)
                            .font(.subheadline)
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                        Spacer()
                        Text(PrivionyxCurrencyFormatter.string(for: summary.amount))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    }
                }
            }
        }
        .privionyxCardStyle()
    }

    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Top Merchants", actionTitle: selectedPeriod.shortTitle)

            ForEach(viewModel.topMerchants(for: selectedPeriod).prefix(5)) { merchant in
                HStack(spacing: 12) {
                    Text(merchant.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)

                    Spacer()

                    Text("\(merchant.receiptCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PrivionyxTheme.Colors.surfaceMuted, in: Capsule())

                    Text(PrivionyxCurrencyFormatter.string(for: merchant.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                }
            }
        }
        .privionyxCardStyle()
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Weekday Pattern", actionTitle: selectedPeriod.shortTitle)

            Chart(viewModel.weekdaySummaries(for: selectedPeriod)) { summary in
                BarMark(
                    x: .value("Day", summary.label),
                    y: .value("Amount", summary.amount)
                )
                .foregroundStyle(PrivionyxTheme.Colors.success.gradient)
                .cornerRadius(6)
            }
            .frame(height: 210)
            .chartYAxis { AxisMarks(position: .leading) }

            Text(viewModel.weekdaySummaryText(for: selectedPeriod))
                .font(.footnote)
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        }
        .privionyxCardStyle()
    }

    private var monthlyDeltaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Monthly Delta", actionTitle: "Last 6 Months")

            Chart(viewModel.monthlyDeltaPoints()) { point in
                BarMark(
                    x: .value("Month", point.label),
                    y: .value("Delta", point.delta)
                )
                .foregroundStyle(point.delta >= 0 ? PrivionyxTheme.Colors.warning.gradient : PrivionyxTheme.Colors.success.gradient)
                .cornerRadius(6)
            }
            .frame(height: 210)
            .chartYAxis { AxisMarks(position: .leading) }

            Text(viewModel.monthlyDeltaSummaryText())
                .font(.footnote)
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        }
        .privionyxCardStyle()
    }

    private var categoryComparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Category Comparison", actionTitle: "Vs Previous")

            ForEach(viewModel.categoryComparisons(for: selectedPeriod)) { comparison in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(comparison.category)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                        Spacer()
                        Text(comparison.deltaText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(comparison.delta >= 0 ? PrivionyxTheme.Colors.warning : PrivionyxTheme.Colors.success)
                    }

                    HStack(spacing: 8) {
                        Capsule()
                            .fill(PrivionyxTheme.Colors.surfaceMuted)
                            .frame(height: 8)
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Capsule()
                                        .fill(comparison.color)
                                        .frame(width: max(10, geometry.size.width * comparison.share))
                                }
                            }
                    }

                    Text("\(PrivionyxCurrencyFormatter.string(for: comparison.currentAmount)) now vs \(PrivionyxCurrencyFormatter.string(for: comparison.previousAmount)) before")
                        .font(.caption)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }
            }
        }
        .privionyxCardStyle()
    }

    private var recentReceiptsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Recent Receipts", actionTitle: "Latest 3")

            ForEach(viewModel.receipts.prefix(3)) { receipt in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PrivionyxTheme.Colors.surfaceMuted)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: receipt.category.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PrivionyxTheme.Colors.accent)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.merchant)
                            .font(.headline)
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(receipt.date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.footnote)
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    }

                    Spacer()

                    Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                }
                .padding(.vertical, 4)
            }
        }
        .privionyxCardStyle()
    }
}

struct DashboardViewModel {
    let appState: PrivionyxAppState

    var receipts: [ReceiptItem] { appState.receipts }

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

    var latestMerchant: String {
        receipts.first?.merchant ?? "None"
    }

    func largestReceiptValue(for period: DashboardPeriod) -> String {
        let value = receipts(in: period).map(\.amount).max() ?? 0
        return PrivionyxCurrencyFormatter.string(for: value)
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
        ReceiptCategory.allCases.map { category in
            let amount = receipts(in: period)
                .filter { $0.category == category }
                .reduce(0) { $0 + $1.amount }

            return CategorySummary(category: category.rawValue, amount: amount, color: color(for: category))
        }
        .filter { $0.amount > 0 }
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
        let scopedReceipts = receipts(in: period)
        let symbols = calendar.shortWeekdaySymbols

        return symbols.enumerated().map { index, symbol in
            let weekdayIndex = index + 1
            let amount = scopedReceipts
                .filter { calendar.component(.weekday, from: $0.date) == weekdayIndex }
                .reduce(0) { $0 + $1.amount }
            return WeekdaySummary(label: symbol, amount: amount)
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
        let currentReceipts = receipts(in: period)
        let previousReceipts = receipts(inPrevious: period)

        let totals = ReceiptCategory.allCases.compactMap { category -> CategoryComparison? in
            let currentAmount = currentReceipts
                .filter { $0.category == category }
                .reduce(0) { $0 + $1.amount }
            let previousAmount = previousReceipts
                .filter { $0.category == category }
                .reduce(0) { $0 + $1.amount }

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

    private func receipts(inPrevious period: DashboardPeriod) -> [ReceiptItem] {
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

struct SpendingChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
}

struct CategorySummary: Identifiable {
    let id = UUID()
    let category: String
    let amount: Double
    let color: Color
}

struct MerchantSummary: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let receiptCount: Int
}

struct WeekdaySummary: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
}

struct MonthlyDeltaPoint: Identifiable {
    let id = UUID()
    let label: String
    let delta: Double
}

struct CategoryComparison: Identifiable {
    let id = UUID()
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

#Preview {
    DashboardView(viewModel: DashboardViewModel(appState: PrivionyxAppState(container: .live(inMemory: true))))
}
