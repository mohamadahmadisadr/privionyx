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
    /// Grouped form of `filteredReceipts`, computed alongside it. It used to be a computed
    /// property read from `body`, which re-grouped everything and built a `DateFormatter`
    /// on every render.
    private(set) var groupedReceipts: [ReceiptMonthGroup] = []

    /// Receipts paired with a pre-folded haystack to match against. Rebuilt only when the
    /// receipts change, so the per-keystroke cost is a plain substring search rather than
    /// six locale-aware comparisons and a currency format per receipt.
    private var searchIndex: [SearchableReceipt] = []
    private var indexedVersion: Int?
    /// The search text the current results were produced for, so filter taps aren't debounced.
    private var appliedSearchText = ""
    private var hasAttemptedRecoveryLoad = false

    /// False until `refresh()` has produced results once.
    ///
    /// Without it the screen reads its own empty starting state as an answer and tells the
    /// user they have saved no receipts, in the moment before it has looked at any.
    private(set) var hasLoadedOnce = false

    /// Whether the screen should be drawing placeholders instead of results — either the
    /// library itself hasn't been read yet, or it has and this screen hasn't filtered it.
    var isLoading: Bool {
        appState.isLoadingLibrary || hasLoadedOnce == false
    }

    /// How long typing has to settle before the list is rebuilt. `.task(id:)` cancels the
    /// previous run when the query changes, so a wait at the top of `refresh()` is all the
    /// debounce needed — an abandoned keystroke never reaches the filter.
    private static let searchDebounce = Duration.milliseconds(200)

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

    private static func grouped(_ receipts: [ReceiptItem]) -> [ReceiptMonthGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        return Dictionary(grouping: receipts) { receipt in
            calendar.dateInterval(of: .month, for: receipt.date)?.start ?? receipt.date
        }
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
        // Only typing is debounced. A category chip or date filter should apply at once, and
        // those leave the search text alone.
        if searchText != appliedSearchText {
            try? await Task.sleep(for: Self.searchDebounce)
            guard Task.isCancelled == false else { return }
        }
        appliedSearchText = searchText

        // A recovery for the case where launch failed to load anything, attempted once.
        // Keyed on having tried rather than on the list being empty, which is otherwise a
        // normal state that made every keystroke re-run a full fetch.
        if appState.receipts.isEmpty, hasAttemptedRecoveryLoad == false {
            hasAttemptedRecoveryLoad = true
            await appState.refreshReceipts()
        }

        rebuildSearchIndexIfNeeded()

        filteredReceipts = filtered(
            searchText: searchText,
            selectedCategory: selectedCategory,
            dateInterval: selectedDateFilter.interval()
        )
        groupedReceipts = Self.grouped(filteredReceipts)
        hasLoadedOnce = true
    }

    private func rebuildSearchIndexIfNeeded() {
        guard indexedVersion != appState.receiptsVersion else { return }

        searchIndex = appState.receipts.map(SearchableReceipt.init(receipt:))
        indexedVersion = appState.receiptsVersion
    }

    private func filtered(
        searchText: String,
        selectedCategory: ReceiptCategory?,
        dateInterval: DateInterval?
    ) -> [ReceiptItem] {
        let query = SearchableReceipt.fold(searchText.trimmingCharacters(in: .whitespacesAndNewlines))

        return searchIndex.compactMap { entry in
            let receipt = entry.receipt

            guard selectedCategory.map({ receipt.category == $0 }) ?? true else { return nil }
            guard dateInterval.map({ $0.contains(receipt.date) }) ?? true else { return nil }
            guard query.isEmpty || entry.haystack.contains(query) else { return nil }

            return receipt
        }
    }
}

/// A receipt flattened into one lowercase, diacritic-folded string covering every field the
/// list searches. Folding each receipt once turns a keystroke into a plain substring scan;
/// the previous filter ran up to six `localizedCaseInsensitiveContains` calls and formatted
/// the amount as currency for every receipt, on every character typed.
private struct SearchableReceipt {
    let receipt: ReceiptItem
    let haystack: String

    init(receipt: ReceiptItem) {
        self.receipt = receipt

        var parts = [
            receipt.merchant,
            receipt.notes,
            receipt.displayCategoryName,
            // Kept so "12.50" still finds a receipt, without paying to format it per keystroke.
            PrivionyxCurrencyFormatter.string(for: receipt.amount)
        ]
        parts.append(contentsOf: receipt.tags)
        if let rawText = receipt.rawText {
            parts.append(rawText)
        }

        haystack = Self.fold(parts.joined(separator: "\n"))
    }

    /// Case- and diacritic-insensitive matching, applied once to each side rather than being
    /// re-derived per comparison. Matches `MerchantRuleService`'s normalisation.
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

struct ReceiptMonthGroup: Identifiable {
    let id: Date
    let title: String
    let receipts: [ReceiptItem]
}
