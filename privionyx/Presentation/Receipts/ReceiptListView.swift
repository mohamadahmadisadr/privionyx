import Observation
import SwiftUI

struct ReceiptListView: View {
    private let appState: PrivionyxAppState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ReceiptListViewModel

    init(appState: PrivionyxAppState) {
        self.appState = appState
        _viewModel = State(initialValue: ReceiptListViewModel(appState: appState))
    }

    var body: some View {
        // Lazy: the month groups below grow with the user's library, and every row was
        // being built up front on each filter change.
        GlassScreen(lazyContent: true, wrapsInNavigationStack: false) {
            header
        } content: {
            summaryCard
            searchField
            filters
            // Between the controls and the results, so it never separates a receipt from
            // the row above it or lands under a thumb reaching for one.
            BannerAdSlot(placement: .receipts)
            receiptGroups
        }
        .task(id: viewModel.queryKey) {
            await viewModel.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            GlassCircleButton(systemImage: "chevron.left", accessibilityTitle: "Back") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Receipts")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text("Search and browse your saved receipts.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.totalSummary)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(viewModel.countSummary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            if viewModel.hasActiveFilters {
                Button("Clear filters") {
                    viewModel.clearFilters()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privionyxCardStyle()
    }

    // MARK: - Filtering

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)

            TextField("Search merchant, note, or tag", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(PrivionyxTheme.Colors.fieldText)

            if viewModel.searchText.isEmpty == false {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .privionyxGlass(cornerRadius: 23)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReceiptDateFilter.allCases) { filter in
                        GlassChip(
                            title: filter.title,
                            isSelected: viewModel.selectedDateFilter == filter
                        ) {
                            viewModel.selectedDateFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GlassChip(
                        title: "All",
                        systemImage: "tag",
                        isSelected: viewModel.selectedCategory == nil
                    ) {
                        viewModel.selectedCategory = nil
                    }

                    ForEach(ReceiptCategory.allCases) { category in
                        GlassChip(
                            title: category.rawValue,
                            systemImage: category.icon,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// Named for what it does rather than for getting started: nothing about this is a step
    /// towards using the app with your own receipts, and a button that reads "Get started"
    /// would be inviting the tap under false pretences.
    private func loadSamples() async {
        do {
            try await appState.loadSampleReceipts()
        } catch {
            appState.lastError = .savingReceipt(error)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var receiptGroups: some View {
        if viewModel.filteredReceipts.isEmpty {
            // Offering samples only when the library is genuinely empty, not merely filtered
            // to nothing — the answer to "no receipts match these filters" is to change the
            // filters, and adding ten receipts instead would be a non-sequitur.
            let isFiltered = viewModel.hasActiveFilters

            GlassEmptyState(
                systemImage: isFiltered ? "line.3.horizontal.decrease" : "tray",
                title: isFiltered ? "No receipts match these filters" : "No receipts saved yet",
                message: isFiltered
                    ? "Try clearing a filter or widening the date range."
                    : "Use the Camera tab to capture a receipt or import a photo — or load a few examples to see how it works.",
                actionTitle: isFiltered ? "Clear filters" : "Load sample receipts",
                action: isFiltered
                    ? { viewModel.clearFilters() }
                    : { Task { await loadSamples() } }
            )
        } else {
            ForEach(viewModel.groupedReceipts) { group in
                VStack(alignment: .leading, spacing: 10) {
                    GlassEyebrow(group.title)

                    GlassRowGroup {
                        ForEach(Array(group.receipts.enumerated()), id: \.element.id) { index, receipt in
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt)
                            } label: {
                                receiptRow(receipt, index: index)
                            }
                            .buttonStyle(.plain)

                            if index < group.receipts.count - 1 {
                                GlassRowDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func receiptRow(_ receipt: ReceiptItem, index: Int) -> some View {
        let isAccented = index.isMultiple(of: 2)

        return HStack(spacing: 12) {
            InitialTile(
                text: receipt.merchant,
                tint: isAccented ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.neutralTile,
                foreground: isAccented ? PrivionyxTheme.Colors.onAccent : PrivionyxTheme.Colors.ink
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.merchant)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)

                Text("\(receipt.displayCategoryName) · \(receipt.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .lineLimit(1)

                if receipt.tags.isEmpty == false {
                    Text(receipt.tags.prefix(2).joined(separator: ", "))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                GlassBadge(title: receipt.status.rawValue, tint: tint(for: receipt.status))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func tint(for status: ReceiptProcessingStatus) -> Color {
        switch status {
        case .scanned:
            PrivionyxTheme.Colors.accent
        case .reviewed:
            PrivionyxTheme.Colors.success
        case .flagged:
            PrivionyxTheme.Colors.warning
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptListView(appState: PrivionyxAppState(container: .preview))
    }
}
