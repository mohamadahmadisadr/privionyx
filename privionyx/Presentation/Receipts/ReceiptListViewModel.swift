import Observation
import Foundation

enum ReceiptDateFilter: String, CaseIterable, Identifiable {
    case all
    case thisMonth
    case last7Days
    case thisYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .thisMonth:
            "This Month"
        case .last7Days:
            "Last 7 Days"
        case .thisYear:
            "This Year"
        }
    }

    func interval(relativeTo currentDate: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all:
            return nil
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: currentDate)) else {
                return nil
            }
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentDate)) ?? currentDate
            return DateInterval(start: start, end: end)
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: currentDate) else { return nil }
            return interval
        case .thisYear:
            guard let interval = calendar.dateInterval(of: .year, for: currentDate) else { return nil }
            return interval
        }
    }
}

@Observable
@MainActor
final class ReceiptListViewModel {
    @ObservationIgnored private let appState: PrivionyxAppState
    var searchText = ""
    var selectedCategory: ReceiptCategory?
    var selectedDateFilter: ReceiptDateFilter = .all
    private(set) var filteredReceipts: [ReceiptItem] = []

    init(appState: PrivionyxAppState) {
        self.appState = appState
    }

    var queryKey: String {
        "\(searchText)|\(selectedCategory?.rawValue ?? "all")|\(selectedDateFilter.rawValue)|\(appState.receiptsVersion)"
    }

    var hasActiveFilters: Bool {
        searchText.isEmpty == false
        || selectedCategory != nil
        || selectedDateFilter != .all
    }

    var categoryFilterTitle: String {
        selectedCategory?.rawValue ?? "All Categories"
    }

    var resultsSummary: String {
        if filteredReceipts.isEmpty {
            return "No matches"
        }

        let receiptWord = filteredReceipts.count == 1 ? "receipt" : "receipts"
        return "\(filteredReceipts.count) \(receiptWord)"
    }

    var totalSummary: String {
        PrivionyxCurrencyFormatter.string(for: filteredReceipts.reduce(0) { $0 + $1.amount })
    }

    var countSummary: String {
        let receiptWord = filteredReceipts.count == 1 ? "receipt" : "receipts"
        if hasActiveFilters {
            return "\(filteredReceipts.count) matching \(receiptWord)"
        }
        return "\(filteredReceipts.count) saved \(receiptWord)"
    }

    var groupedReceipts: [ReceiptMonthGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: filteredReceipts) { receipt in
            calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
        }

        return grouped
            .map { month, receipts in
                ReceiptMonthGroup(
                    id: month,
                    title: formatter.string(from: month),
                    receipts: receipts.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.id > $1.id }
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        selectedDateFilter = .all
    }

    func refresh() async {
        if appState.receipts.isEmpty {
            await appState.refreshReceipts()
        }
        filteredReceipts = filtered(
            searchText: searchText,
            selectedCategory: selectedCategory,
            dateInterval: selectedDateFilter.interval()
        )
    }

    private func filtered(
        searchText: String,
        selectedCategory: ReceiptCategory?,
        dateInterval: DateInterval?
    ) -> [ReceiptItem] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return appState.receipts.filter { receipt in
            let matchesCategory = selectedCategory.map { receipt.category == $0 } ?? true
            let matchesSearch = normalizedSearch.isEmpty
                || receipt.merchant.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.notes.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.displayCategoryName.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.tags.contains(where: { $0.localizedCaseInsensitiveContains(normalizedSearch) })
                || PrivionyxCurrencyFormatter.string(for: receipt.amount).localizedCaseInsensitiveContains(normalizedSearch)
                || (receipt.rawText?.localizedCaseInsensitiveContains(normalizedSearch) ?? false)
            let matchesDate = dateInterval.map { $0.contains(receipt.date) } ?? true

            return matchesCategory && matchesSearch && matchesDate
        }
    }
}

struct ReceiptMonthGroup: Identifiable {
    let id: Date
    let title: String
    let receipts: [ReceiptItem]
}
