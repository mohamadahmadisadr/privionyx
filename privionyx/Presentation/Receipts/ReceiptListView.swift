import Observation
import SwiftUI

struct ReceiptListView: View {
    private let appState: PrivionyxAppState
    @State private var viewModel: ReceiptListViewModel

    init(appState: PrivionyxAppState) {
        self.appState = appState
        _viewModel = State(initialValue: ReceiptListViewModel(appState: appState))
    }

    var body: some View {
        PrivionyxScreen(
            title: "Receipts",
            subtitle: "A simple history of the receipts saved on this device."
        ) {
            summarySection
            searchSection
            filterSection
            receiptsSection
        }
        .task(id: viewModel.queryKey) {
            await viewModel.refresh()
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.totalSummary)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(viewModel.countSummary)
                        .font(.subheadline)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer()

                Image(systemName: "doc.text.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 46, height: 46)
                    .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if viewModel.hasActiveFilters {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .buttonStyle(.plain)
            }
        }
        .privionyxCardStyle()
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                TextField("Search merchant, note, or tag", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(PrivionyxTheme.Colors.fieldText)

                if viewModel.searchText.isEmpty == false {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(14)
            .background(PrivionyxTheme.Colors.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .privionyxCardStyle()
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Date", selection: $viewModel.selectedDateFilter) {
                ForEach(ReceiptDateFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Button("All Categories") {
                    viewModel.selectedCategory = nil
                }

                ForEach(ReceiptCategory.allCases) { category in
                    Button(category.rawValue) {
                        viewModel.selectedCategory = category
                    }
                }
            } label: {
                HStack {
                    Label(viewModel.categoryFilterTitle, systemImage: "tag")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .padding(14)
                .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .privionyxCardStyle()
    }

    private var receiptsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Receipt History", actionTitle: viewModel.filteredReceipts.isEmpty ? nil : viewModel.resultsSummary)

            if viewModel.filteredReceipts.isEmpty {
                EmptyStateCard(
                    systemImage: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle" : "tray",
                    title: viewModel.hasActiveFilters ? "No receipts match these filters" : "No receipts saved yet",
                    message: viewModel.hasActiveFilters
                        ? "Try clearing a filter or widening the amount and date range."
                        : "Use the Add tab to scan a receipt or import a photo."
                )
            } else {
                ForEach(viewModel.groupedReceipts) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                        VStack(spacing: 10) {
                            ForEach(group.receipts) { receipt in
                                receiptRow(receipt)
                            }
                        }
                    }
                }
            }
        }
        .privionyxCardStyle()
    }

    private func receiptRow(_ receipt: ReceiptItem) -> some View {
        NavigationLink {
            ReceiptDetailView(receipt: receipt)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: receipt.category.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.merchant)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    HStack(spacing: 6) {
                        Text(receipt.displayCategoryName)
                            .lineLimit(1)
                        Text("•")
                        Text(receipt.date, format: .dateTime.month(.abbreviated).day().year())
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                    if receipt.tags.isEmpty == false {
                        Text(receipt.tags.prefix(2).joined(separator: ", "))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}

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
            "Month"
        case .last7Days:
            "7 Days"
        case .thisYear:
            "Year"
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
        filteredReceipts = appState.filteredReceipts(
            searchText: searchText,
            selectedCategory: selectedCategory,
            dateInterval: selectedDateFilter.interval(),
            minimumAmount: nil,
            maximumAmount: nil
        )
    }
}

struct ReceiptMonthGroup: Identifiable {
    let id: Date
    let title: String
    let receipts: [ReceiptItem]
}

#Preview {
    ReceiptListView(appState: PrivionyxAppState(container: .live(inMemory: true)))
}
